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
        repo.nextAnalyzeResult = makeAnalyzeResult()
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
        repo.nextAnalyzeResult = makeAnalyzeResult()
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
        repo.nextAnalyzeResult = makeAnalyzeResult()
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        viewModel.validatedImage = StarterValidatedImage(
            jpegData: Data(repeating: 1, count: 12_000),
            qualityScore: 0.88,
            qualityIssue: "slightly dark",
            pixelSize: CGSize(width: 820, height: 820)
        )

        await viewModel.analyzeStarter(starterID: starterID, userID: UUID())
        await viewModel.savePendingAnalysis(starterID: starterID)

        XCTAssertEqual(repo.lastPersistInput?.promptVersion, "v1-server")
        XCTAssertEqual(repo.lastPersistInput?.model, "gpt-4o-mini")
        XCTAssertEqual(repo.lastPersistInput?.response.starterState, "active")
        XCTAssertEqual(repo.lastPersistInput?.qualityIssue, "slightly dark")
    }

    func testRefreshHomeContextUsesLatestActiveStarterAfterListChange() async {
        let starterA = makeStarter(id: UUID(), active: true, name: "Starter A")
        let starterB = makeStarter(id: UUID(), active: true, name: "Starter B")
        let repo = FakeStarterRepository(starters: [starterA])
        repo.listStartersResponses = [[starterA], [starterB]]
        repo.starterStatesByStarterID[starterB.id] = StarterState(
            starterID: starterB.id,
            userID: UUID(),
            stateLabel: "ready",
            updatedFromScanID: UUID(),
            updatedAt: Date()
        )
        repo.feedingLogsByStarterID[starterB.id] = [makeFeedingLog(starterID: starterB.id)]
        repo.timelineByStarterID[starterB.id] = [makeTimelineItem(starterID: starterB.id)]

        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        await viewModel.loadStarters()
        await viewModel.refreshHomeContext()

        XCTAssertEqual(viewModel.activeStarter?.id, starterB.id)
        XCTAssertEqual(repo.lastStarterStateRequestID, starterB.id)
        XCTAssertEqual(repo.lastFeedingHistoryRequestID, starterB.id)
        XCTAssertEqual(repo.lastTimelineRequestID, starterB.id)
    }

    func testRefreshHomeContextClearsStaleChildStateWhenActiveStarterChanges() async {
        let starterA = makeStarter(id: UUID(), active: true, name: "Starter A")
        let starterB = makeStarter(id: UUID(), active: true, name: "Starter B")
        let repo = FakeStarterRepository(starters: [starterA])
        repo.listStartersResponses = [[starterA], [starterB]]
        repo.starterStateError = TestVMError.refreshFailed
        repo.feedingHistoryError = TestVMError.refreshFailed
        repo.timelineError = TestVMError.refreshFailed

        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)
        await viewModel.loadStarters()
        viewModel.starterState = StarterState(
            starterID: starterA.id,
            userID: UUID(),
            stateLabel: "old",
            updatedFromScanID: UUID(),
            updatedAt: Date()
        )
        viewModel.feedingLogs = [makeFeedingLog(starterID: starterA.id)]
        viewModel.timeline = [makeTimelineItem(starterID: starterA.id)]

        await viewModel.refreshHomeContext()

        XCTAssertNil(viewModel.starterState)
        XCTAssertTrue(viewModel.feedingLogs.isEmpty)
        XCTAssertTrue(viewModel.timeline.isEmpty)
    }

    func testRefreshHomeContextClearsChildStateWhenNoStartersRemain() async {
        let starterA = makeStarter(id: UUID(), active: true, name: "Starter A")
        let repo = FakeStarterRepository(starters: [starterA])
        repo.listStartersResponses = [[starterA], []]
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)

        await viewModel.loadStarters()
        viewModel.starterState = StarterState(
            starterID: starterA.id,
            userID: UUID(),
            stateLabel: "active",
            updatedFromScanID: UUID(),
            updatedAt: Date()
        )
        viewModel.feedingLogs = [makeFeedingLog(starterID: starterA.id)]
        viewModel.timeline = [makeTimelineItem(starterID: starterA.id)]

        await viewModel.refreshHomeContext()

        XCTAssertTrue(viewModel.starters.isEmpty)
        XCTAssertNil(viewModel.starterState)
        XCTAssertTrue(viewModel.feedingLogs.isEmpty)
        XCTAssertTrue(viewModel.timeline.isEmpty)
    }

    func testRefreshHomeContextLoadsAllChildStateForActiveStarter() async {
        let starter = makeStarter(id: UUID(), active: true, name: "Starter")
        let starterState = StarterState(
            starterID: starter.id,
            userID: UUID(),
            stateLabel: "healthy",
            updatedFromScanID: UUID(),
            updatedAt: Date()
        )
        let feedingLog = makeFeedingLog(starterID: starter.id)
        let timelineItem = makeTimelineItem(starterID: starter.id)
        let repo = FakeStarterRepository(starters: [starter])
        repo.starterStatesByStarterID[starter.id] = starterState
        repo.feedingLogsByStarterID[starter.id] = [feedingLog]
        repo.timelineByStarterID[starter.id] = [timelineItem]
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)

        await viewModel.refreshHomeContext()

        XCTAssertEqual(viewModel.activeStarter?.id, starter.id)
        XCTAssertEqual(viewModel.starterState?.stateLabel, "healthy")
        XCTAssertEqual(viewModel.feedingLogs.count, 1)
        XCTAssertEqual(viewModel.feedingLogs.first?.starterID, starter.id)
        XCTAssertEqual(viewModel.timeline.count, 1)
        XCTAssertEqual(viewModel.timeline.first?.scan.starterID, starter.id)
    }

    func testRefreshHomeContextFailureKeepsStarterListAndSetsSafeError() async {
        let starter = makeStarter(id: UUID(), active: true, name: "Starter")
        let repo = FakeStarterRepository(starters: [starter])
        let viewModel = StarterWorkflowViewModel(repository: repo, analytics: NoopStarterAnalytics(), isProUser: true)

        await viewModel.loadStarters()
        repo.listStartersError = TestVMError.refreshFailed
        await viewModel.refreshHomeContext()

        XCTAssertEqual(viewModel.starters.count, 1)
        XCTAssertEqual(
            viewModel.errorMessage,
            AppError.unknown("Something went wrong. Please try again.").localizedDescription
        )
    }

    private func makeStarter(id: UUID = UUID(), active: Bool, name: String) -> Starter {
        Starter(
            id: id,
            userID: UUID(),
            name: name,
            hydrationPreference: 100,
            createdAt: Date(),
            active: active
        )
    }

    private func makeFeedingLog(starterID: UUID) -> FeedingLog {
        FeedingLog(
            id: UUID(),
            userID: UUID(),
            starterID: starterID,
            loggedAt: Date(),
            roomTempC: 24.0,
            flourG: 50,
            waterG: 50,
            starterG: 20,
            notes: nil
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

    private func makeAnalyzeResult() -> StarterAnalyzeResult {
        StarterAnalyzeResult(
            model: "gpt-4o-mini",
            promptVersion: "v1-server",
            analysis: makeAIResponse()
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

    private func makeTimelineItem(starterID: UUID) -> StarterTimelineItem {
        StarterTimelineItem(
            id: UUID(),
            scan: makeScan(starterID: starterID),
            analysis: nil,
            recommendation: makeRecommendation(outcome: RecommendationOutcome.unknown.rawValue)
        )
    }
}

private final class FakeStarterRepository: StarterRepository {
    var starters: [Starter]
    var listStartersResponses: [[Starter]] = []
    var listStartersError: Error?
    var nextAnalyzeResult: StarterAnalyzeResult?
    var nextStarterState: StarterState?
    var timeline: [StarterTimelineItem] = []
    var persistError: Error?
    var analyzeCallCount = 0
    var starterStatesByStarterID: [UUID: StarterState] = [:]
    var feedingLogsByStarterID: [UUID: [FeedingLog]] = [:]
    var timelineByStarterID: [UUID: [StarterTimelineItem]] = [:]
    var starterStateError: Error?
    var feedingHistoryError: Error?
    var timelineError: Error?
    var lastStarterStateRequestID: UUID?
    var lastFeedingHistoryRequestID: UUID?
    var lastTimelineRequestID: UUID?
    private var listStartersCallIndex = 0
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

    func listStarters() async throws -> [Starter] {
        if let listStartersError {
            throw listStartersError
        }
        if !listStartersResponses.isEmpty {
            let response = listStartersResponses[min(listStartersCallIndex, listStartersResponses.count - 1)]
            listStartersCallIndex += 1
            return response
        }
        return starters
    }
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter {
        let starter = Starter(id: UUID(), userID: UUID(), name: name, hydrationPreference: hydrationPreference, createdAt: Date(), active: active)
        starters.insert(starter, at: 0)
        return starter
    }
    func setActiveStarter(starterID: UUID) async throws {}
    func fetchStarter(starterID: UUID) async throws -> Starter {
        starters.first ?? Starter(id: starterID, userID: UUID(), name: "Starter", hydrationPreference: nil, createdAt: Date(), active: true)
    }
    func fetchStarterState(starterID: UUID) async throws -> StarterState? {
        lastStarterStateRequestID = starterID
        if let starterStateError {
            throw starterStateError
        }
        if let mapped = starterStatesByStarterID[starterID] {
            return mapped
        }
        return nextStarterState
    }
    func createFeedingLog(starterID: UUID, loggedAt: Date, roomTempC: Double, flourG: Int?, waterG: Int?, starterG: Int?, notes: String?) async throws -> FeedingLog {
        FeedingLog(id: UUID(), userID: UUID(), starterID: starterID, loggedAt: loggedAt, roomTempC: roomTempC, flourG: flourG, waterG: waterG, starterG: starterG, notes: notes)
    }
    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] {
        lastFeedingHistoryRequestID = starterID
        if let feedingHistoryError {
            throw feedingHistoryError
        }
        return feedingLogsByStarterID[starterID] ?? []
    }
    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String {
        "path/\(starterID).jpg"
    }
    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAnalyzeResult {
        analyzeCallCount += 1
        return nextAnalyzeResult ?? StarterAnalyzeResult(
            model: "gpt-4o-mini",
            promptVersion: "v1",
            analysis: StarterAIResponse(
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
        )
    }
    func persistStarterAnalysis(starterID: UUID, imagePath: String, qualityScore: Double?, qualityIssue: String?, model: String, promptVersion: String, response: StarterAIResponse) async throws -> PersistedStarterAnalysisIDs {
        lastPersistInput = (starterID, imagePath, qualityScore, qualityIssue, model, promptVersion, response)
        if let persistError { throw persistError }
        return PersistedStarterAnalysisIDs(scanID: UUID(), analysisID: UUID(), recommendationID: UUID())
    }
    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] {
        lastTimelineRequestID = starterID
        if let timelineError {
            throw timelineError
        }
        if let mapped = timelineByStarterID[starterID] {
            return mapped
        }
        return timeline
    }
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

private enum TestVMError: Error {
    case refreshFailed
}

