import Foundation

struct Starter: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let name: String
    let hydrationPreference: Double?
    let createdAt: Date
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case hydrationPreference = "hydration_preference"
        case createdAt = "created_at"
        case active
    }
}

struct FeedingLog: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let starterID: UUID
    let loggedAt: Date
    let roomTempC: Double
    let flourG: Int?
    let waterG: Int?
    let starterG: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case starterID = "starter_id"
        case loggedAt = "logged_at"
        case roomTempC = "room_temp_c"
        case flourG = "flour_g"
        case waterG = "water_g"
        case starterG = "starter_g"
        case notes
    }
}

struct StarterScan: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let starterID: UUID?
    let bakeID: UUID?
    let scanType: String
    let storagePath: String
    let createdAt: Date
    let status: String
    let qualityScore: Double?
    let qualityIssue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case starterID = "starter_id"
        case bakeID = "bake_id"
        case scanType = "scan_type"
        case storagePath = "storage_path"
        case createdAt = "created_at"
        case status
        case qualityScore = "quality_score"
        case qualityIssue = "quality_issue"
    }
}

struct StarterAnalysis: Codable, Equatable, Identifiable {
    let id: UUID
    let scanID: UUID
    let userID: UUID
    let model: String
    let promptVersion: String
    let confidence: Double
    let analysisJSON: JSONValue
    let renderedExplanation: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case scanID = "scan_id"
        case userID = "user_id"
        case model
        case promptVersion = "prompt_version"
        case confidence
        case analysisJSON = "analysis_json"
        case renderedExplanation = "rendered_explanation"
        case createdAt = "created_at"
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct StarterState: Codable, Equatable {
    let starterID: UUID
    let userID: UUID
    let stateLabel: String
    let updatedFromScanID: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case starterID = "starter_id"
        case userID = "user_id"
        case stateLabel = "state_label"
        case updatedFromScanID = "updated_from_scan_id"
        case updatedAt = "updated_at"
    }
}

struct Recommendation: Codable, Equatable, Identifiable {
    let id: UUID
    let userID: UUID
    let scanID: UUID
    let recommendation: String
    let dueAt: Date?
    let completedAt: Date?
    let outcome: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case scanID = "scan_id"
        case recommendation
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case outcome
        case createdAt = "created_at"
    }
}

struct StarterTimelineItem: Identifiable, Equatable {
    let id: UUID
    let scan: StarterScan
    let analysis: StarterAnalysis?
    let recommendation: Recommendation?
}

enum RecommendationOutcome: String, CaseIterable {
    case followed
    case helpful
    case notHelpful = "not_helpful"
    case skipped
    case unknown
}

