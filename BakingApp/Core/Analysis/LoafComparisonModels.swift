import Foundation

enum LoafComparisonMode: String, Codable, Equatable {
    case baseline
    case processComparison
    case fullComparison
}

/// Loaf quality score classification (never used for process values).
enum ScoreClassification: String, Codable, Equatable {
    case improved
    case regressed
    case unchanged
}

/// Process journal change direction (never improved/regressed).
enum ProcessChangeDirection: String, Codable, Equatable {
    case increased
    case decreased
    case unchanged
}

struct BakeProcessSnapshot: Codable, Equatable {
    let doughHydrationPercent: Double
    let bulkFermentationMinutes: Int
    let finalProofMinutes: Int
    let fermentationTemperatureCelsius: Double?
    let ovenTemperatureCelsius: Double
    let bakingTimeMinutes: Int

    enum CodingKeys: String, CodingKey {
        case doughHydrationPercent = "dough_hydration_percent"
        case bulkFermentationMinutes = "bulk_fermentation_minutes"
        case finalProofMinutes = "final_proof_minutes"
        case fermentationTemperatureCelsius = "fermentation_temperature_c"
        case ovenTemperatureCelsius = "oven_temperature_c"
        case bakingTimeMinutes = "baking_time_minutes"
    }

    init(bake: Bake) {
        doughHydrationPercent = bake.doughHydrationPercent
        bulkFermentationMinutes = bake.bulkFermentationMinutes
        finalProofMinutes = bake.finalProofMinutes
        fermentationTemperatureCelsius = bake.fermentationTemperatureCelsius
        ovenTemperatureCelsius = bake.ovenTemperatureCelsius
        bakingTimeMinutes = bake.bakingTimeMinutes
    }

    init(
        doughHydrationPercent: Double,
        bulkFermentationMinutes: Int,
        finalProofMinutes: Int,
        fermentationTemperatureCelsius: Double?,
        ovenTemperatureCelsius: Double,
        bakingTimeMinutes: Int
    ) {
        self.doughHydrationPercent = doughHydrationPercent
        self.bulkFermentationMinutes = bulkFermentationMinutes
        self.finalProofMinutes = finalProofMinutes
        self.fermentationTemperatureCelsius = fermentationTemperatureCelsius
        self.ovenTemperatureCelsius = ovenTemperatureCelsius
        self.bakingTimeMinutes = bakingTimeMinutes
    }
}

struct LoafScoreSnapshot: Codable, Equatable {
    let crumbScore: Int
    let crustScore: Int
    let ovenSpringScore: Int
    let overallScore: Int

    enum CodingKeys: String, CodingKey {
        case crumbScore = "crumb_score"
        case crustScore = "crust_score"
        case ovenSpringScore = "oven_spring_score"
        case overallScore = "overall_score"
    }

    init(analysis: LoafAIAnalysis) {
        crumbScore = analysis.crumbScore
        crustScore = analysis.crustScore
        ovenSpringScore = analysis.ovenSpringScore
        overallScore = analysis.overallScore
    }

    init(crumbScore: Int, crustScore: Int, ovenSpringScore: Int, overallScore: Int) {
        self.crumbScore = crumbScore
        self.crustScore = crustScore
        self.ovenSpringScore = ovenSpringScore
        self.overallScore = overallScore
    }
}

struct PreviousBakeRef: Equatable {
    let bake: Bake
    let starterChanged: Bool
}

struct ScoreDeltaSnapshot: Codable, Equatable, Identifiable {
    var id: String { dimension }
    let dimension: String
    let previous: Int
    let current: Int
    let delta: Int
    let classification: ScoreClassification

    var label: String {
        switch dimension {
        case "crumb": return "Crumb"
        case "crust": return "Crust"
        case "oven_spring": return "Oven spring"
        case "overall": return "Overall"
        default: return dimension
        }
    }
}

struct ProcessDeltaSnapshot: Codable, Equatable, Identifiable {
    var id: String { dimension }
    let dimension: String
    let previous: Double
    let current: Double
    let delta: Double
    let change: ProcessChangeDirection

    var label: String {
        switch dimension {
        case "hydration": return "Hydration"
        case "bulk_fermentation": return "Bulk fermentation"
        case "final_proof": return "Final proof"
        case "fermentation_temperature": return "Fermentation temp"
        case "oven_temperature": return "Oven temperature"
        case "bake_time": return "Bake time"
        default: return dimension
        }
    }
}

/// Stable comparison snapshot persisted inside `ai_analyses.analysis_json`.
struct LoafComparisonSnapshot: Codable, Equatable {
    let comparisonMode: LoafComparisonMode
    let previousBakeID: UUID?
    let previousStarterID: UUID?
    let starterChanged: Bool
    let scoreDeltas: [ScoreDeltaSnapshot]
    let processDeltas: [ProcessDeltaSnapshot]
    let recommendation: String

    enum CodingKeys: String, CodingKey {
        case comparisonMode = "comparison_mode"
        case previousBakeID = "previous_bake_id"
        case previousStarterID = "previous_starter_id"
        case starterChanged = "starter_changed"
        case scoreDeltas = "score_deltas"
        case processDeltas = "process_deltas"
        case recommendation
    }
}

struct LoafComparisonPresentation: Equatable {
    let mode: LoafComparisonMode
    let previousBakeID: UUID?
    let previousBakeName: String?
    let previousStarterID: UUID?
    let starterChanged: Bool
    let baselineMessage: String?
    let visualComparisonUnavailableMessage: String?
    let scoreDeltas: [ScoreDeltaSnapshot]
    let processDeltas: [ProcessDeltaSnapshot]
    let assessment: String
    let why: String
    let recommendation: String
    let strengths: [String]
    let issues: [String]
    let scores: LoafScoreSnapshot
    /// Canonical snapshot used for persistence / historical reload.
    let snapshot: LoafComparisonSnapshot
}

struct LoafAnalyzeContext: Codable, Equatable {
    let comparisonMode: LoafComparisonMode
    let currentProcess: BakeProcessSnapshot
    let previousBakeID: UUID?
    let previousBakeName: String?
    let starterChanged: Bool
    let previousProcess: BakeProcessSnapshot?
    let previousScores: LoafScoreSnapshot?

    enum CodingKeys: String, CodingKey {
        case comparisonMode = "comparison_mode"
        case currentProcess = "current_process"
        case previousBakeID = "previous_bake_id"
        case previousBakeName = "previous_bake_name"
        case starterChanged = "starter_changed"
        case previousProcess = "previous_process"
        case previousScores = "previous_scores"
    }
}

enum LoafComparisonThresholds {
    /// Score: delta >= +threshold → improved; delta <= -threshold → regressed; else unchanged.
    static let scorePoints = 5
    static let hydrationPercent = 1.0
    static let minutes = 15
    static let temperatureCelsius = 2.0
}
