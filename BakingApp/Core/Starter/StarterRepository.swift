import Foundation

struct AnalyzeStarterPayload: Codable {
    let starterID: UUID
    let imagePath: String
    let promptVersion: String

    enum CodingKeys: String, CodingKey {
        case starterID = "starter_id"
        case imagePath = "image_path"
        case promptVersion = "prompt_version"
    }
}

struct PersistedStarterAnalysisIDs: Codable, Equatable {
    let scanID: UUID
    let analysisID: UUID
    let recommendationID: UUID

    enum CodingKeys: String, CodingKey {
        case scanID = "scan_id"
        case analysisID = "analysis_id"
        case recommendationID = "recommendation_id"
    }
}

struct StarterAnalyzeResult: Equatable {
    let model: String?
    let promptVersion: String?
    let outcome: StarterAnalyzeOutcome
}

enum StarterAnalyzeOutcome: Equatable {
    case starterAnalysis(StarterAIResponse)
    case invalidSubject(reason: InvalidSubjectReason, message: String)
}

enum InvalidSubjectReason: String, Codable, Equatable {
    case notStarter = "not_starter"
    case uncertain
}

protocol StarterRepository {
    func listStarters() async throws -> [Starter]
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter
    func setActiveStarter(starterID: UUID) async throws
    func fetchStarter(starterID: UUID) async throws -> Starter
    func fetchStarterState(starterID: UUID) async throws -> StarterState?

    func createFeedingLog(
        starterID: UUID,
        loggedAt: Date,
        roomTempC: Double,
        flourG: Int?,
        waterG: Int?,
        starterG: Int?,
        notes: String?
    ) async throws -> FeedingLog
    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog]

    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String
    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAnalyzeResult
    func persistStarterAnalysis(
        starterID: UUID,
        imagePath: String,
        qualityScore: Double?,
        qualityIssue: String?,
        model: String,
        promptVersion: String,
        response: StarterAIResponse
    ) async throws -> PersistedStarterAnalysisIDs
    func fetchRecommendation(recommendationID: UUID) async throws -> Recommendation
    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem]
    func updateRecommendationOutcome(recommendationID: UUID, outcome: RecommendationOutcome) async throws -> Recommendation
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL
}

