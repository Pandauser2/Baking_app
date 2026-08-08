import Foundation

enum LoafComparisonMode: String, Codable, Equatable {
    case baseline
    case processComparison
    case fullComparison
}

enum ComparisonTrend: String, Codable, Equatable {
    case improved
    case regressed
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

struct DimensionDelta: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let previousDisplay: String
    let currentDisplay: String
    let trend: ComparisonTrend
    let deltaDisplay: String?
}

struct LoafComparisonPresentation: Equatable {
    let mode: LoafComparisonMode
    let previousBakeID: UUID?
    let previousBakeName: String?
    let starterChanged: Bool
    let baselineMessage: String?
    let visualComparisonUnavailableMessage: String?
    let scoreDeltas: [DimensionDelta]
    let processDeltas: [DimensionDelta]
    let assessment: String
    let why: String
    let recommendation: String
    let strengths: [String]
    let issues: [String]
    let scores: LoafScoreSnapshot
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
    /// Absolute score points; |delta| <= this → unchanged.
    static let scorePoints = 3
    /// Absolute hydration percent points.
    static let hydrationPercent = 1.0
    /// Absolute minutes for fermentation / bake time.
    static let minutes = 15
    /// Absolute °C for oven / fermentation temperature.
    static let temperatureCelsius = 2.0
}
