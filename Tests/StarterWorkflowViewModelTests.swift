import Foundation
import CoreGraphics
import XCTest
@testable import BakingApp

@MainActor
final class StarterWorkflowViewModelTests: XCTestCase {
    func testActiveStarterSelectionPrefersActive() async {
        let active = makeStarter(active: true, name: "Active")
        let inactive = makeStarter(active: false, name: "Inactive")
        let repo = FakeStarterRepository(starters: [inactive, active])
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)

        await viewModel.loadStarters()

        XCTAssertEqual(viewModel.activeStarter?.name, "Active")
    }

    func testNonProGatingPreventsAnalyze() async {
        let repo = FakeStarterRepository()
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: false)

        await viewModel.analyzeStarter(starterID: UUID(), userID: UUID())

        XCTAssertEqual(viewModel.errorMessage, AppError.subscriptionRequired.errorDescription)
        XCTAssertEqual(repo.analyzeCallCount, 0)
    }

    func testPersistenceRetryDoesNotRecallAI() async {
        let starterID = UUID()
        let repo = FakeStarterRepository()
        repo.nextAnalyzeResponse = makeAIResponse()
        repo.persistError = AppError.unknown("Save failed")
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        viewModel.validatedImage = StarterValidatedImage(
            jpegData: Data(repeating: 1, count: 12_000),
            qualityScore: 0.9,
            qualityIssue: nil,
            pixelSize: CGSize(width: 800, height: 800)
        )

        await viewModel.analyzeStarter(starterID: starterID, userID: UUID())
        await viewModel.savePendingAnalysis(starterID: starterID)
        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertNotNil(viewModel.pendingAIResponse)

        repo.persistError = nil
        await viewModel.savePendingAnalysis(starterID: starterID)
        XCTAssertEqual(repo.analyzeCallCount, 1)
        XCTAssertNotNil(viewModel.persistedIDs)
    }

    func testRecommendationOutcomeTransitionUpdatesRecommendation() async {
        let starterID = UUID()
        let recommendation = makeRecommendation(outcome: RecommendationOutcome.unknown.rawValue)
        let repo = FakeStarterRepository()
        repo.timeline = [StarterTimelineItem(id: UUID(), scan: makeScan(starterID: starterID), analysis: nil, recommendation: recommendation)]
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)

        await viewModel.loadTimeline(starterID: starterID)
        await viewModel.markRecommendationOutcome(.helpful)

        XCTAssertEqual(viewModel.recommendation?.outcome, RecommendationOutcome.helpful.rawValue)
    }

    func testStarterStateUpdateMappingAfterSave() async {
        let starterID = UUID()
        let repo = FakeStarterRepository()
        repo.nextAnalyzeResponse = makeAIResponse()
        repo.nextStarterState = StarterState(
            starterID: starterID,
            userID: UUID(),
            stateLabel: "active",
            updatedFromScanID: UUID(),
            updatedAt: Date()
        )
        repo.timeline = [StarterTimelineItem(id: UUID(), scan: makeScan(starterID: starterID), analysis: nil, recommendation: makeRecommendation(outcome: RecommendationOutcome.unknown.rawValue))]
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        viewModel.validatedImage = StarterValidatedImage(
            jpegData: Data(repeating: 1, count: 12_000),
            qualityScore: 0.7,
            qualityIssue: "dark",
            pixelSize: CGSize(width: 900, height: 900)
        )

        await viewModel.analyzeStarter(starterID: starterID, userID: UUID())
        await viewModel.savePendingAnalysis(starterID: starterID)

        XCTAssertEqual(viewModel.starterState?.stateLabel, "active")
    }

    func testPersistenceMappingSendsExpectedFields() async {
        let starterID = UUID()
        let repo = FakeStarterRepository()
        repo.nextAnalyzeResponse = makeAIResponse()
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        viewModel.validatedImage = StarterValidatedImage(
            jpegData: Data(repeating: 1, count: 12_000),
            qualityScore: 0.88,
            qualityIssue: "slightly dark",
            pixelSize: CGSize(width: 820, height: 820)
        )

        await viewModel.analyzeStarter(starterID: starterID, userID: UUID())
        await viewModel.savePendingAnalysis(starterID: starterID)

        XCTAssertEqual(repo.lastPersistInput?.promptVersion, "v1")
        XCTAssertEqual(repo.lastPersistInput?.response.starterState, "active")
        XCTAssertEqual(repo.lastPersistInput?.qualityIssue, "slightly dark")
    }

    private func makeStarter(active: Bool, name: String) -> Starter {
        Starter(
            id: UUID(),
            userID: UUID(),
            name: name,
            hydrationPreference: 100,
            createdAt: Date(),
            active: active
        )
    }

    private func makeAIResponse() -> StarterAIResponse {
        StarterAIResponse(
            scanType: "starter",
            observations: ["Bubbles visible"],
            diagnosis: ["active"],
            confidence: 0.8,
            nextSteps: [.init(instruction: "Feed now", timeWindowHours: 12)],
            humanExplanation: "Looks active.",
            riskFlags: [],
            compareToPrevious: .init(changed: true, explanation: "More bubbles"),
            starterState: "active"
        )
    }

    private func makeScan(starterID: UUID) -> StarterScan {
        StarterScan(
            id: UUID(),
            userID: UUID(),
            starterID: starterID,
            bakeID: nil,
            scanType: "starter",
            storagePath: "user/\(starterID)/2026/07/test.jpg",
            createdAt: Date(),
            status: "analyzed",
            qualityScore: 0.8,
            qualityIssue: nil
        )
    }

    private func makeRecommendation(outcome: String) -> Recommendation {
        Recommendation(
            id: UUID(),
            userID: UUID(),
            scanID: UUID(),
            recommendation: "Feed now",
            dueAt: Date(),
            completedAt: nil,
            outcome: outcome,
            createdAt: Date()
        )
    }
}

private final class FakeStarterRepository: StarterRepository {
    var starters: [Starter]
    var nextAnalyzeResponse: StarterAIResponse?
    var nextStarterState: StarterState?
    var timeline: [StarterTimelineItem] = []
    var persistError: Error?
    var analyzeCallCount = 0
    var lastPersistInput: (
        starterID: UUID,
        imagePath: String,
        qualityScore: Double?,
        qualityIssue: String?,
        model: String,
        promptVersion: String,
        response: StarterAIResponse
    )?

    init(starters: [Starter] = []) {
        self.starters = starters
    }

    func listStarters() async throws -> [Starter] { starters }
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter {
        let starter = Starter(id: UUID(), userID: UUID(), name: name, hydrationPreference: hydrationPreference, createdAt: Date(), active: active)
        starters.insert(starter, at: 0)
        return starter
    }
    func setActiveStarter(starterID: UUID) async throws {}
    func fetchStarter(starterID: UUID) async throws -> Starter {
        starters.first ?? Starter(id: starterID, userID: UUID(), name: "Starter", hydrationPreference: nil, createdAt: Date(), active: true)
    }
    func fetchStarterState(starterID: UUID) async throws -> StarterState? { nextStarterState }
    func createFeedingLog(starterID: UUID, loggedAt: Date, roomTempC: Double, flourG: Int?, waterG: Int?, starterG: Int?, notes: String?) async throws -> FeedingLog {
        FeedingLog(id: UUID(), userID: UUID(), starterID: starterID, loggedAt: loggedAt, roomTempC: roomTempC, flourG: flourG, waterG: waterG, starterG: starterG, notes: notes)
    }
    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] { [] }
    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String {
        "path/\(starterID).jpg"
    }
    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAIResponse {
        analyzeCallCount += 1
        return nextAnalyzeResponse ?? StarterAIResponse(
            scanType: "starter",
            observations: ["Bubbles visible"],
            diagnosis: ["active"],
            confidence: 0.7,
            nextSteps: [.init(instruction: "Feed now", timeWindowHours: 12)],
            humanExplanation: "Looks active.",
            riskFlags: [],
            compareToPrevious: .init(changed: true, explanation: "More bubbles"),
            starterState: "active"
        )
    }
    func persistStarterAnalysis(starterID: UUID, imagePath: String, qualityScore: Double?, qualityIssue: String?, model: String, promptVersion: String, response: StarterAIResponse) async throws -> PersistedStarterAnalysisIDs {
        lastPersistInput = (starterID, imagePath, qualityScore, qualityIssue, model, promptVersion, response)
        if let persistError { throw persistError }
        return PersistedStarterAnalysisIDs(scanID: UUID(), analysisID: UUID(), recommendationID: UUID())
    }
    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] { timeline }
    func updateRecommendationOutcome(recommendationID: UUID, outcome: RecommendationOutcome) async throws -> Recommendation {
        let updated = Recommendation(
            id: recommendationID,
            userID: UUID(),
            scanID: UUID(),
            recommendation: "Feed now",
            dueAt: Date(),
            completedAt: Date(),
            outcome: outcome.rawValue,
            createdAt: Date()
        )
        return updated
    }
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL { URL(string: "https://example.com")! }
}

private struct NoopStarterAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {}
}

