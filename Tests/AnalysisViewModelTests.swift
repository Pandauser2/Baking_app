import Foundation
import UIKit
import XCTest
@testable import BakingApp

@MainActor
final class AnalysisViewModelTests: XCTestCase {
    func testHistoryReloadUsesRepository() async {
        let expected = sampleScan()
        let repo = FakeLoafAnalysisRepository(history: [expected])
        let viewModel = AnalysisViewModel(repository: repo, analytics: NoopAnalytics())

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.history, [expected])
    }

    func testMalformedResponseSetsFriendlyError() async {
        let repo = FakeLoafAnalysisRepository(analyzeError: AppError.malformedResponse)
        let viewModel = AnalysisViewModel(repository: repo, isProUser: true, analytics: NoopAnalytics())
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))

        await viewModel.analyze(userID: UUID())

        XCTAssertEqual(viewModel.errorMessage, AppError.malformedResponse.errorDescription)
    }

    func testProGateBlocksAnalyze() async {
        let repo = FakeLoafAnalysisRepository(analyzeResult: sampleAnalyzeResult())
        let viewModel = AnalysisViewModel(repository: repo, isProUser: false, analytics: NoopAnalytics())
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))
        await viewModel.analyze(userID: UUID())
        XCTAssertEqual(viewModel.errorMessage, AppError.subscriptionRequired.errorDescription)
        XCTAssertEqual(repo.analyzeCallCount, 0)
    }

    func testAnalyzeWithBakeIDPersistsAndBuildsComparison() async {
        let bakeID = UUID()
        let bake = sampleBake(id: bakeID, name: "Current", bakedAt: Date())
        let result = sampleAnalyzeResult()
        let persisted = PersistedLoafAnalysisIDs(scanID: UUID(), analysisID: UUID())
        let repo = FakeLoafAnalysisRepository(
            analyzeResult: result,
            persistIDs: persisted,
            bakeAnalyses: [
                CanonicalLoafAnalysis(
                    scanID: persisted.scanID,
                    analysisID: persisted.analysisID,
                    bakeID: bakeID,
                    storagePath: "user/2026/08/file.jpg",
                    model: result.model,
                    promptVersion: result.promptVersion,
                    confidence: result.analysis.confidence,
                    analysis: result.analysis,
                    renderedExplanation: result.analysis.summary,
                    createdAt: Date()
                )
            ]
        )
        let bakeRepo = FakeBakeRepository(bakes: [bake])
        let viewModel = AnalysisViewModel(
            repository: repo,
            bakeID: bakeID,
            bakeRepository: bakeRepo,
            isProUser: true,
            analytics: NoopAnalytics()
        )
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))

        await viewModel.analyze(userID: UUID())

        XCTAssertEqual(viewModel.latestResult, result)
        XCTAssertEqual(viewModel.latestPersistedIDs, persisted)
        XCTAssertEqual(viewModel.comparison?.mode, .baseline)
        XCTAssertEqual(repo.persistCallCount, 1)
        XCTAssertEqual(repo.lastPersistedBakeID, bakeID)
        XCTAssertNotNil(repo.lastAnalyzeContext)
    }

    func testPersistMismatchRejection() async {
        let bakeID = UUID()
        let bake = sampleBake(id: bakeID, name: "Current", bakedAt: Date())
        let repo = FakeLoafAnalysisRepository(
            analyzeResult: sampleAnalyzeResult(),
            persistError: AppError.unknown(LoafPersistMismatchError.storagePathLinkedToDifferentBake.errorDescription ?? "mismatch")
        )
        let viewModel = AnalysisViewModel(
            repository: repo,
            bakeID: bakeID,
            bakeRepository: FakeBakeRepository(bakes: [bake]),
            isProUser: true,
            analytics: NoopAnalytics()
        )
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))
        await viewModel.analyze(userID: UUID())
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("different bake") == true)
    }

    private func sampleScan() -> LoafScan {
        LoafScan(
            id: UUID(),
            userID: UUID(),
            imagePath: "abc/2026/07/file.jpg",
            crumbScore: 70,
            crustScore: 75,
            ovenSpringScore: 67,
            overallScore: 72,
            strengths: ["Good crust"],
            improvements: ["More steam"],
            nextSteps: ["Shorter final proof"],
            aiSummary: "Strong loaf.",
            promptVersion: "v1",
            createdAt: Date()
        )
    }

    private func sampleAnalyzeResult() -> LoafAnalyzeResult {
        LoafAnalyzeResult(
            model: "gpt-4o-mini",
            promptVersion: "v1",
            analysis: LoafAIAnalysis(
                crumbScore: 70,
                crustScore: 75,
                ovenSpringScore: 67,
                overallScore: 72,
                strengths: ["Good crust"],
                improvements: ["More steam"],
                nextSteps: ["Shorter final proof"],
                summary: "Strong loaf.",
                why: "Baseline why"
            )
        )
    }

    private func sampleBake(id: UUID, name: String, bakedAt: Date) -> Bake {
        Bake(
            id: id,
            userID: UUID(),
            starterID: UUID(),
            bakedAt: bakedAt,
            name: name,
            doughHydrationPercent: 75,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            mixingMethod: "Hand mix",
            shapingMethod: "Boule",
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

    private func patternImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
            context.fill(CGRect(x: size.width / 2, y: size.height / 2, width: size.width / 2, height: size.height / 2))
        }
    }
}

private final class FakeBakeRepository: BakeRepository {
    var bakes: [Bake]
    init(bakes: [Bake]) { self.bakes = bakes }
    func listBakes() async throws -> [Bake] { bakes }
    func fetchBake(bakeID: UUID) async throws -> Bake {
        guard let bake = bakes.first(where: { $0.id == bakeID }) else {
            throw AppError.unknown("missing")
        }
        return bake
    }
    func createBake(_ input: BakeCreateInput) async throws -> Bake {
        throw AppError.unknown("unused")
    }
}

private final class FakeLoafAnalysisRepository: LoafAnalysisRepository {
    var uploadedPath: String = "user/2026/07/file.jpg"
    var analyzeResult: LoafAnalyzeResult?
    var history: [LoafScan] = []
    var bakeAnalyses: [CanonicalLoafAnalysis] = []
    var analyzeError: Error?
    var persistError: Error?
    var persistIDs: PersistedLoafAnalysisIDs?
    private(set) var persistCallCount = 0
    private(set) var analyzeCallCount = 0
    private(set) var lastPersistedBakeID: UUID?
    private(set) var lastAnalyzeContext: LoafAnalyzeContext?

    init(
        history: [LoafScan] = [],
        analyzeResult: LoafAnalyzeResult? = nil,
        analyzeError: Error? = nil,
        persistIDs: PersistedLoafAnalysisIDs? = nil,
        persistError: Error? = nil,
        bakeAnalyses: [CanonicalLoafAnalysis] = []
    ) {
        self.history = history
        self.analyzeResult = analyzeResult
        self.analyzeError = analyzeError
        self.persistIDs = persistIDs
        self.persistError = persistError
        self.bakeAnalyses = bakeAnalyses
    }

    func uploadImage(_ data: Data, userID: UUID) async throws -> String {
        uploadedPath
    }

    func analyzeLoaf(
        imagePath: String,
        promptVersion: String,
        context: LoafAnalyzeContext?
    ) async throws -> LoafAnalyzeResult {
        analyzeCallCount += 1
        lastAnalyzeContext = context
        if let analyzeError { throw analyzeError }
        if let analyzeResult { return analyzeResult }
        throw AppError.analysisFailed
    }

    func persistLoafAnalysis(
        bakeID: UUID,
        imagePath: String,
        result: LoafAnalyzeResult,
        qualityScore: Double?,
        qualityIssue: String?
    ) async throws -> PersistedLoafAnalysisIDs {
        persistCallCount += 1
        lastPersistedBakeID = bakeID
        if let persistError { throw persistError }
        if let persistIDs { return persistIDs }
        throw AppError.unknown("persist failed")
    }

    func fetchHistory() async throws -> [LoafScan] {
        history
    }

    func fetchLoafAnalyses(forBakeID bakeID: UUID) async throws -> [CanonicalLoafAnalysis] {
        bakeAnalyses.filter { $0.bakeID == bakeID }
    }

    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        URL(string: "https://example.com")!
    }
}

private struct NoopAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {}
}
