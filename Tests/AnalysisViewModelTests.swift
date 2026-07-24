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

private struct FakeLoafAnalysisRepository: LoafAnalysisRepository {
    var uploadedPath: String = "user/2026/07/file.jpg"
    var scan: LoafScan?
    var history: [LoafScan] = []
    var analyzeError: Error?

    func uploadImage(_ data: Data, userID: UUID) async throws -> String {
        uploadedPath
    }

    func analyzeLoaf(imagePath: String, promptVersion: String) async throws -> LoafScan {
        if let analyzeError { throw analyzeError }
        if let scan { return scan }
        throw AppError.analysisFailed
    }

    func fetchHistory() async throws -> [LoafScan] {
        history
    }

    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        URL(string: "https://example.com/image.jpg")!
    }
}

private struct NoopAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {}
}

