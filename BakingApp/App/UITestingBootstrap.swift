import Foundation

enum UITestingBootstrap {
    static let argument = "-uiTesting"
    static let populatedTimelineArgument = "-uiTestingTimelinePopulated"
    static let seedAnalysisResultArgument = "-uiTestingSeedAnalysisResult"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var usesPopulatedTimeline: Bool {
        ProcessInfo.processInfo.arguments.contains(populatedTimelineArgument)
    }

    static var shouldSeedAnalysisResult: Bool {
        ProcessInfo.processInfo.arguments.contains(seedAnalysisResultArgument)
    }

    static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let starterID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static func makeStarter() -> Starter {
        Starter(
            id: starterID,
            userID: userID,
            name: "UITest Starter",
            hydrationPreference: 100,
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            active: true
        )
    }

    static func makeTimelineItem() -> StarterTimelineItem {
        let scanID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let analysisID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let recommendationID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let createdAt = Date(timeIntervalSince1970: 1_720_000_100)
        let scan = StarterScan(
            id: scanID,
            userID: userID,
            starterID: starterID,
            bakeID: nil,
            scanType: "starter",
            storagePath: "uitest/path.jpg",
            createdAt: createdAt,
            status: "analyzed",
            qualityScore: 0.9,
            qualityIssue: nil
        )
        let analysis = StarterAnalysis(
            id: analysisID,
            scanID: scanID,
            userID: userID,
            model: "uitest",
            promptVersion: "v2",
            confidence: 0.9,
            analysisJSON: .object(["starter_state": .string("active")]),
            renderedExplanation: "UITest saved analysis remains intact.",
            createdAt: createdAt
        )
        let recommendation = Recommendation(
            id: recommendationID,
            userID: userID,
            scanID: scanID,
            recommendation: "Feed now",
            dueAt: nil,
            completedAt: Date(timeIntervalSince1970: 1_720_000_200),
            outcome: RecommendationOutcome.followed.rawValue,
            createdAt: createdAt
        )
        return StarterTimelineItem(id: scanID, scan: scan, analysis: analysis, recommendation: recommendation)
    }
}

struct UITestingAuthClient: AuthClient {
    var authCallbackURL: URL { URL(string: "bakingapp://auth-callback")! }

    func restoreSession() async throws -> UserSession? {
        UserSession(userID: UITestingBootstrap.userID, email: "uitest@example.com")
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        .signedIn(UserSession(userID: UITestingBootstrap.userID, email: email))
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        UserSession(userID: UITestingBootstrap.userID, email: email)
    }

    func handleAuthCallback(url: URL) async throws -> UserSession {
        UserSession(userID: UITestingBootstrap.userID, email: "uitest@example.com")
    }

    func signOut() async throws {}
}

struct UITestingStarterRepository: StarterRepository {
    private let starter = UITestingBootstrap.makeStarter()
    private let timeline: [StarterTimelineItem]

    init(populatedTimeline: Bool) {
        timeline = populatedTimeline ? [UITestingBootstrap.makeTimelineItem()] : []
    }

    func listStarters() async throws -> [Starter] { [starter] }
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter { starter }
    func setActiveStarter(starterID: UUID) async throws {}
    func fetchStarter(starterID: UUID) async throws -> Starter { starter }
    func fetchStarterState(starterID: UUID) async throws -> StarterState? {
        StarterState(
            starterID: starter.id,
            userID: starter.userID,
            stateLabel: "active",
            updatedFromScanID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_100)
        )
    }

    func createFeedingLog(
        starterID: UUID,
        loggedAt: Date,
        roomTempC: Double,
        flourG: Int?,
        waterG: Int?,
        starterG: Int?,
        notes: String?
    ) async throws -> FeedingLog {
        FeedingLog(
            id: UUID(),
            userID: starter.userID,
            starterID: starter.id,
            loggedAt: loggedAt,
            roomTempC: roomTempC,
            flourG: flourG,
            waterG: waterG,
            starterG: starterG,
            notes: notes
        )
    }

    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] { [] }
    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String {
        "uitest/path.jpg"
    }

    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAnalyzeResult {
        StarterAnalyzeResult(
            model: "uitest",
            promptVersion: promptVersion,
            outcome: .starterAnalysis(
                StarterAIResponse(
                    scanType: "starter",
                    observations: ["UITest bubbles"],
                    diagnosis: ["active"],
                    confidence: 0.9,
                    nextSteps: [
                        StarterAIResponse.NextStep(instruction: "Feed now", timeWindowHours: 12)
                    ],
                    humanExplanation: "UITest analysis",
                    riskFlags: [],
                    compareToPrevious: StarterAIResponse.CompareToPrevious(
                        changed: false,
                        explanation: "No previous data to compare."
                    ),
                    starterState: "active"
                )
            )
        )
    }

    func persistStarterAnalysis(
        starterID: UUID,
        imagePath: String,
        qualityScore: Double?,
        qualityIssue: String?,
        model: String,
        promptVersion: String,
        response: StarterAIResponse
    ) async throws -> PersistedStarterAnalysisIDs {
        PersistedStarterAnalysisIDs(
            scanID: UUID(),
            analysisID: UUID(),
            recommendationID: UUID()
        )
    }

    func fetchRecommendation(recommendationID: UUID) async throws -> Recommendation {
        Recommendation(
            id: recommendationID,
            userID: starter.userID,
            scanID: UUID(),
            recommendation: "Feed now",
            dueAt: nil,
            completedAt: nil,
            outcome: RecommendationOutcome.unknown.rawValue,
            createdAt: Date()
        )
    }

    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] { timeline }

    func updateRecommendationOutcome(
        recommendationID: UUID,
        outcome: RecommendationOutcome
    ) async throws -> Recommendation {
        Recommendation(
            id: recommendationID,
            userID: starter.userID,
            scanID: UUID(),
            recommendation: "Feed now",
            dueAt: nil,
            completedAt: Date(),
            outcome: outcome.rawValue,
            createdAt: Date()
        )
    }

    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
