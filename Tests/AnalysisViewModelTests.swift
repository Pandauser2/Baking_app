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
        let viewModel = AnalysisViewModel(repository: repo, analytics: NoopAnalytics())
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))

        await viewModel.analyze(userID: UUID())

        XCTAssertEqual(viewModel.errorMessage, AppError.malformedResponse.errorDescription)
    }

    func testAnalyzeWithBakeIDPersistsAndReloads() async {
        let bakeID = UUID()
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
        let viewModel = AnalysisViewModel(repository: repo, bakeID: bakeID, analytics: NoopAnalytics())
        viewModel.handleCapturedImage(patternImage(size: CGSize(width: 1200, height: 1200)))

        await viewModel.analyze(userID: UUID())

        XCTAssertEqual(viewModel.latestResult, result)
        XCTAssertEqual(viewModel.latestPersistedIDs, persisted)
        XCTAssertEqual(viewModel.bakeAnalyses.count, 1)
        XCTAssertEqual(repo.persistCallCount, 1)
        XCTAssertEqual(repo.lastPersistedBakeID, bakeID)
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
                summary: "Strong loaf."
            )
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

private final class FakeLoafAnalysisRepository: LoafAnalysisRepository {
    var uploadedPath: String = "user/2026/07/file.jpg"
    var analyzeResult: LoafAnalyzeResult?
    var history: [LoafScan] = []
    var bakeAnalyses: [CanonicalLoafAnalysis] = []
    var analyzeError: Error?
    var persistIDs: PersistedLoafAnalysisIDs?
    private(set) var persistCallCount = 0
    private(set) var lastPersistedBakeID: UUID?

    init(
        history: [LoafScan] = [],
        analyzeResult: LoafAnalyzeResult? = nil,
        analyzeError: Error? = nil,
        persistIDs: PersistedLoafAnalysisIDs? = nil,
        bakeAnalyses: [CanonicalLoafAnalysis] = []
    ) {
        self.history = history
        self.analyzeResult = analyzeResult
        self.analyzeError = analyzeError
        self.persistIDs = persistIDs
        self.bakeAnalyses = bakeAnalyses
    }

    func uploadImage(_ data: Data, userID: UUID) async throws -> String {
        uploadedPath
    }

    func analyzeLoaf(imagePath: String, promptVersion: String) async throws -> LoafAnalyzeResult {
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
        URL(string: "https://example.com/image.jpg")!
    }
}

private struct NoopAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {}
}
