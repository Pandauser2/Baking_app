import Foundation

/// Legacy Phase B score-card row from `public.loaf_scans` (read-only for history).
struct LoafScan: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let imagePath: String
    let crumbScore: Int?
    let crustScore: Int?
    let ovenSpringScore: Int?
    let overallScore: Int?
    let strengths: [String]
    let improvements: [String]
    let nextSteps: [String]
    let aiSummary: String?
    let promptVersion: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case imagePath = "image_path"
        case crumbScore = "crumb_score"
        case crustScore = "crust_score"
        case ovenSpringScore = "oven_spring_score"
        case overallScore = "overall_score"
        case strengths
        case improvements
        case nextSteps = "next_steps"
        case aiSummary = "ai_summary"
        case promptVersion = "prompt_version"
        case createdAt = "created_at"
    }
}

struct LoafAIAnalysis: Codable, Equatable {
    let crumbScore: Int
    let crustScore: Int
    let ovenSpringScore: Int
    let overallScore: Int
    let strengths: [String]
    let improvements: [String]
    let nextSteps: [String]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case crumbScore = "crumb_score"
        case crustScore = "crust_score"
        case ovenSpringScore = "oven_spring_score"
        case overallScore = "overall_score"
        case strengths
        case improvements
        case nextSteps = "next_steps"
        case summary
    }

    var confidence: Double {
        Double(overallScore) / 100.0
    }
}

struct LoafAnalyzeResult: Codable, Equatable {
    let model: String
    let promptVersion: String
    let analysis: LoafAIAnalysis

    enum CodingKeys: String, CodingKey {
        case model
        case promptVersion = "prompt_version"
        case analysis
    }
}

struct PersistedLoafAnalysisIDs: Codable, Equatable {
    let scanID: UUID
    let analysisID: UUID

    enum CodingKeys: String, CodingKey {
        case scanID = "scan_id"
        case analysisID = "analysis_id"
    }
}

struct CanonicalLoafAnalysis: Equatable, Identifiable {
    var id: UUID { scanID }
    let scanID: UUID
    let analysisID: UUID
    let bakeID: UUID?
    let storagePath: String
    let model: String
    let promptVersion: String
    let confidence: Double
    let analysis: LoafAIAnalysis
    let renderedExplanation: String
    let createdAt: Date
}

struct AnalyzeLoafPayload: Codable, Equatable {
    let imagePath: String
    let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case imagePath = "image_path"
        case promptVersion = "prompt_version"
    }
}

struct PersistLoafAnalysisPayload: Codable, Equatable {
    let bakeID: UUID
    let storagePath: String
    let model: String
    let promptVersion: String
    let confidence: Double
    let analysisJSON: LoafAIAnalysis
    let renderedExplanation: String
    let qualityScore: Double?
    let qualityIssue: String?

    enum CodingKeys: String, CodingKey {
        case bakeID = "p_bake_id"
        case storagePath = "p_storage_path"
        case model = "p_model"
        case promptVersion = "p_prompt_version"
        case confidence = "p_confidence"
        case analysisJSON = "p_analysis_json"
        case renderedExplanation = "p_rendered_explanation"
        case qualityScore = "p_quality_score"
        case qualityIssue = "p_quality_issue"
    }
}

enum LoafAnalyzeResponseParser {
    static func decode(_ data: Data) throws -> LoafAnalyzeResult {
        try JSONDecoder().decode(LoafAnalyzeResult.self, from: data)
    }
}

enum PersistLoafAnalysisResponseDecoder {
    static func decodeIDs(_ data: Data) throws -> PersistedLoafAnalysisIDs {
        let decoder = SupabaseJSONDecoder.make()
        if let decoded = try? decoder.decode(PersistedLoafAnalysisIDs.self, from: data) {
            return decoded
        }
        if let list = try? decoder.decode([PersistedLoafAnalysisIDs].self, from: data),
           let first = list.first {
            return first
        }
        throw AppError.malformedResponse
    }
}

enum LoafScanParser {
    static func decodeScanResponse(_ data: Data) throws -> LoafScan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let scan = try? decoder.decode(LoafScan.self, from: data) {
            return scan
        }
        if let wrapped = try? decoder.decode(WrappedScan.self, from: data) {
            return wrapped.scan
        }
        throw AppError.malformedResponse
    }

    private struct WrappedScan: Codable {
        let scan: LoafScan
    }
}
