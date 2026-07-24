import Foundation

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

struct AnalyzeLoafPayload: Codable, Equatable {
    let imagePath: String
    let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case imagePath = "image_path"
        case promptVersion = "prompt_version"
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

