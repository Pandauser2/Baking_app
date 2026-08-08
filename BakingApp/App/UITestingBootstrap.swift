import Foundation

enum UITestingBootstrap {
    static let argument = "-uiTesting"
    static let populatedTimelineArgument = "-uiTestingTimelinePopulated"
    static let seedAnalysisResultArgument = "-uiTestingSeedAnalysisResult"
    static let loafBaselineArgument = "-uiTestingLoafBaseline"
    static let loafProcessComparisonArgument = "-uiTestingLoafProcessComparison"
    static let loafFullComparisonArgument = "-uiTestingLoafFullComparison"
    static let loafAnalyzeFailArgument = "-uiTestingLoafAnalyzeFail"
    static let loafAutoAnalyzeArgument = "-uiTestingLoafAutoAnalyze"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var usesPopulatedTimeline: Bool {
        ProcessInfo.processInfo.arguments.contains(populatedTimelineArgument)
    }

    static var shouldSeedAnalysisResult: Bool {
        ProcessInfo.processInfo.arguments.contains(seedAnalysisResultArgument)
    }

    static var loafBaselineMode: Bool {
        ProcessInfo.processInfo.arguments.contains(loafBaselineArgument)
    }

    static var loafProcessComparisonMode: Bool {
        ProcessInfo.processInfo.arguments.contains(loafProcessComparisonArgument)
    }

    static var loafFullComparisonMode: Bool {
        ProcessInfo.processInfo.arguments.contains(loafFullComparisonArgument)
    }

    static var loafAnalyzeShouldFail: Bool {
        ProcessInfo.processInfo.arguments.contains(loafAnalyzeFailArgument)
    }

    static var loafAutoAnalyze: Bool {
        ProcessInfo.processInfo.arguments.contains(loafAutoAnalyzeArgument)
    }

    static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let starterID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let bakeAID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let bakeBID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

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

final class UITestingBakeRepository: BakeRepository {
    private let starterRepository: StarterRepository
    private var bakes: [Bake] = []

    init(starterRepository: StarterRepository) {
        self.starterRepository = starterRepository
    }

    func seedForUITestingIfNeeded() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        func makeBake(id: UUID, name: String, bakedAt: Date, hydration: Double) -> Bake {
            Bake(
                id: id,
                userID: UITestingBootstrap.userID,
                starterID: UITestingBootstrap.starterID,
                bakedAt: bakedAt,
                name: name,
                doughHydrationPercent: hydration,
                bulkFermentationMinutes: 240,
                finalProofMinutes: 120,
                mixingMethod: BakeMixingMethod.hand.rawValue,
                shapingMethod: BakeShapingMethod.boule.rawValue,
                ovenTemperatureCelsius: 230,
                bakingTimeMinutes: 40,
                resultRating: 4,
                fermentationTemperatureCelsius: 24,
                fermentationTemperatureSource: .room,
                retardationMinutes: nil,
                numberOfFolds: nil,
                steamingMethod: nil,
                flourNotes: nil,
                notes: nil,
                createdAt: bakedAt,
                updatedAt: bakedAt
            )
        }

        if UITestingBootstrap.loafBaselineMode {
            bakes = [makeBake(id: UITestingBootstrap.bakeAID, name: "Baseline Bake", bakedAt: now, hydration: 75)]
        } else if UITestingBootstrap.loafProcessComparisonMode || UITestingBootstrap.loafFullComparisonMode {
            bakes = [
                makeBake(id: UITestingBootstrap.bakeBID, name: "Second Bake", bakedAt: now.addingTimeInterval(86_400), hydration: 78),
                makeBake(id: UITestingBootstrap.bakeAID, name: "First Bake", bakedAt: now, hydration: 72),
            ]
        }
    }

    func listBakes() async throws -> [Bake] {
        bakes.sorted { $0.bakedAt > $1.bakedAt }
    }

    func fetchBake(bakeID: UUID) async throws -> Bake {
        guard let bake = bakes.first(where: { $0.id == bakeID }) else {
            throw AppError.unknown("Bake not found")
        }
        return bake
    }

    func createBake(_ input: BakeCreateInput) async throws -> Bake {
        let validated = try BakeValidation.validate(input)
        _ = try await starterRepository.fetchStarter(starterID: validated.starterID)
        let now = Date()
        let bake = Bake(
            id: UUID(),
            userID: UITestingBootstrap.userID,
            starterID: validated.starterID,
            bakedAt: validated.bakedAt,
            name: validated.name,
            doughHydrationPercent: validated.doughHydrationPercent,
            bulkFermentationMinutes: validated.bulkFermentationMinutes,
            finalProofMinutes: validated.finalProofMinutes,
            mixingMethod: validated.mixingMethod,
            shapingMethod: validated.shapingMethod,
            ovenTemperatureCelsius: validated.ovenTemperatureCelsius,
            bakingTimeMinutes: validated.bakingTimeMinutes,
            resultRating: validated.resultRating,
            fermentationTemperatureCelsius: validated.fermentationTemperatureCelsius,
            fermentationTemperatureSource: validated.fermentationTemperatureSource,
            retardationMinutes: validated.retardationMinutes,
            numberOfFolds: validated.numberOfFolds,
            steamingMethod: validated.steamingMethod,
            flourNotes: validated.flourNotes,
            notes: validated.notes,
            createdAt: now,
            updatedAt: now
        )
        bakes.insert(bake, at: 0)
        return bake
    }
}

final class UITestingLoafAnalysisRepository: LoafAnalysisRepository {
    private let bakeRepository: UITestingBakeRepository
    private var analysesByBake: [UUID: CanonicalLoafAnalysis] = [:]
    private var persistedByPath: [String: (bakeID: UUID, ids: PersistedLoafAnalysisIDs)] = [:]

    init(bakeRepository: UITestingBakeRepository) {
        self.bakeRepository = bakeRepository
        seed()
    }

    private func seed() {
        if UITestingBootstrap.loafBaselineMode {
            analysesByBake[UITestingBootstrap.bakeAID] = makeCanonical(
                bakeID: UITestingBootstrap.bakeAID,
                path: "uitest/bake-baseline.jpg",
                overall: 74,
                crumb: 72,
                crust: 76,
                spring: 70
            )
        }
        if UITestingBootstrap.loafFullComparisonMode {
            analysesByBake[UITestingBootstrap.bakeAID] = makeCanonical(
                bakeID: UITestingBootstrap.bakeAID,
                path: "uitest/bake-a.jpg",
                overall: 70,
                crumb: 68,
                crust: 72,
                spring: 69
            )
        }
    }

    private func makeCanonical(
        bakeID: UUID,
        path: String,
        overall: Int,
        crumb: Int,
        crust: Int,
        spring: Int,
        comparison: LoafComparisonSnapshot? = nil
    ) -> CanonicalLoafAnalysis {
        let recommendation = "Increase steam"
        let snapshot = comparison ?? LoafComparisonSnapshot(
            comparisonMode: .baseline,
            previousBakeID: nil,
            previousStarterID: nil,
            starterChanged: false,
            scoreDeltas: [],
            processDeltas: [],
            recommendation: recommendation
        )
        let analysis = LoafAIAnalysis(
            crumbScore: crumb,
            crustScore: crust,
            ovenSpringScore: spring,
            overallScore: overall,
            strengths: ["Open crumb"],
            improvements: ["Shape tension"],
            nextSteps: [recommendation],
            summary: "UITest loaf assessment.",
            why: "UITest why explanation.",
            comparison: snapshot
        )
        return CanonicalLoafAnalysis(
            scanID: UUID(),
            analysisID: UUID(),
            bakeID: bakeID,
            storagePath: path,
            model: "uitest",
            promptVersion: "v1",
            confidence: analysis.confidence,
            analysis: analysis,
            renderedExplanation: analysis.summary,
            createdAt: Date()
        )
    }

    func uploadImage(_ data: Data, userID: UUID) async throws -> String {
        "\(userID.uuidString.lowercased())/2026/08/\(UUID().uuidString.lowercased()).jpg"
    }

    func analyzeLoaf(
        imagePath: String,
        promptVersion: String,
        context: LoafAnalyzeContext?
    ) async throws -> LoafAnalyzeResult {
        if UITestingBootstrap.loafAnalyzeShouldFail {
            throw AppError.analysisFailed
        }
        let mode = context?.comparisonMode ?? .baseline
        let why: String
        switch mode {
        case .baseline:
            why = "Establishing baseline for future comparisons."
        case .processComparison:
            why = "Process changed; visual comparison unavailable."
        case .fullComparison:
            why = "Scores and process shifted versus previous bake."
        }
        return LoafAnalyzeResult(
            model: "uitest",
            promptVersion: promptVersion,
            analysis: LoafAIAnalysis(
                crumbScore: 78,
                crustScore: 80,
                ovenSpringScore: 74,
                overallScore: 77,
                strengths: ["Better crumb"],
                improvements: ["More steam"],
                nextSteps: ["Add steam for first 15 minutes"],
                summary: "Solid loaf for UITest \(mode.rawValue).",
                why: why
            )
        )
    }

    func persistLoafAnalysis(
        bakeID: UUID,
        imagePath: String,
        result: LoafAnalyzeResult,
        qualityScore: Double?,
        qualityIssue: String?
    ) async throws -> PersistedLoafAnalysisIDs {
        if let existing = persistedByPath[imagePath] {
            if existing.bakeID != bakeID {
                throw AppError.unknown(LoafPersistMismatchError.storagePathLinkedToDifferentBake.errorDescription ?? "mismatch")
            }
            return existing.ids
        }
        let ids = PersistedLoafAnalysisIDs(scanID: UUID(), analysisID: UUID())
        persistedByPath[imagePath] = (bakeID, ids)
        analysesByBake[bakeID] = CanonicalLoafAnalysis(
            scanID: ids.scanID,
            analysisID: ids.analysisID,
            bakeID: bakeID,
            storagePath: imagePath,
            model: result.model,
            promptVersion: result.promptVersion,
            confidence: result.analysis.confidence,
            analysis: result.analysis,
            renderedExplanation: result.analysis.summary,
            createdAt: Date()
        )
        return ids
    }

    func fetchHistory() async throws -> [LoafScan] { [] }

    func fetchLoafAnalyses(forBakeID bakeID: UUID) async throws -> [CanonicalLoafAnalysis] {
        if let analysis = analysesByBake[bakeID] {
            return [analysis]
        }
        return []
    }

    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
