import Foundation
import XCTest
@testable import BakingApp

final class LoafComparisonEngineTests: XCTestCase {
    private let starterA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let starterB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let user = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testPreviousBakePrefersSameStarter() {
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(3), name: "C")
        let olderSame = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A")
        let newerOther = makeBake(id: UUID(), starter: starterB, bakedAt: date(2), name: "B")
        let selected = PreviousBakeSelector.select(current: current, from: [current, newerOther, olderSame])
        XCTAssertEqual(selected?.bake.name, "A")
        XCTAssertEqual(selected?.starterChanged, false)
    }

    func testPreviousBakeFallsBackAndFlagsStarterChanged() {
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(3), name: "C")
        let priorOther = makeBake(id: UUID(), starter: starterB, bakedAt: date(2), name: "B")
        let selected = PreviousBakeSelector.select(current: current, from: [current, priorOther])
        XCTAssertEqual(selected?.bake.name, "B")
        XCTAssertEqual(selected?.starterChanged, true)
    }

    func testNeverSelectsSelfOrFuture() {
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "Now")
        let future = makeBake(id: UUID(), starter: starterA, bakedAt: date(3), name: "Future")
        XCTAssertNil(PreviousBakeSelector.select(current: current, from: [current, future]))
    }

    func testBaselineMode() {
        let bake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "First")
        let analysis = sampleAnalysis(overall: 70)
        let presentation = LoafComparisonEngine.buildPresentation(
            currentBake: bake,
            currentAnalysis: analysis,
            previous: nil,
            previousAnalysis: nil,
            why: "Baseline why",
            recommendation: "Keep hydration"
        )
        XCTAssertEqual(presentation.mode, .baseline)
        XCTAssertEqual(presentation.baselineMessage, LoafComparisonEngine.baselineMessage)
        XCTAssertFalse(presentation.baselineMessage?.contains("No previous data to compare.") == true)
        XCTAssertTrue(presentation.scoreDeltas.isEmpty)
    }

    func testProcessComparisonMode() {
        let previousBake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A", hydration: 70)
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "B", hydration: 78)
        let presentation = LoafComparisonEngine.buildPresentation(
            currentBake: current,
            currentAnalysis: sampleAnalysis(overall: 75),
            previous: PreviousBakeRef(bake: previousBake, starterChanged: false),
            previousAnalysis: nil,
            why: "Process only",
            recommendation: "Hold proof"
        )
        XCTAssertEqual(presentation.mode, .processComparison)
        XCTAssertNotNil(presentation.visualComparisonUnavailableMessage)
        XCTAssertFalse(presentation.processDeltas.isEmpty)
        XCTAssertTrue(presentation.scoreDeltas.isEmpty)
    }

    func testFullComparisonModeAndThresholds() {
        let previousBake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A")
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "B")
        let previousAnalysis = CanonicalLoafAnalysis(
            scanID: UUID(),
            analysisID: UUID(),
            bakeID: previousBake.id,
            storagePath: "a.jpg",
            model: "t",
            promptVersion: "v1",
            confidence: 0.7,
            analysis: sampleAnalysis(overall: 70, crumb: 70, crust: 70, spring: 70),
            renderedExplanation: "prev",
            createdAt: date(1)
        )
        let presentation = LoafComparisonEngine.buildPresentation(
            currentBake: current,
            currentAnalysis: sampleAnalysis(overall: 80, crumb: 72, crust: 70, spring: 65),
            previous: PreviousBakeRef(bake: previousBake, starterChanged: false),
            previousAnalysis: previousAnalysis,
            why: "Because steam",
            recommendation: "Add steam"
        )
        XCTAssertEqual(presentation.mode, .fullComparison)
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 72, previous: 70), .unchanged)
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 80, previous: 70), .improved)
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 65, previous: 70), .regressed)
        let overall = presentation.scoreDeltas.first { $0.label == "Overall" }
        XCTAssertEqual(overall?.trend, .improved)
        let crust = presentation.scoreDeltas.first { $0.label == "Crust" }
        XCTAssertEqual(crust?.trend, .unchanged)
    }

    func testMissingOptionalFermentationTempSkipped() {
        var previous = BakeProcessSnapshot(
            doughHydrationPercent: 70,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            fermentationTemperatureCelsius: nil,
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40
        )
        let current = BakeProcessSnapshot(
            doughHydrationPercent: 70,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            fermentationTemperatureCelsius: 24,
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40
        )
        let deltas = LoafComparisonEngine.makeProcessDeltas(current: current, previous: previous)
        XCTAssertFalse(deltas.contains { $0.label == "Fermentation temp" })
        _ = previous
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + day * 86_400))
    }

    private func makeBake(
        id: UUID,
        starter: UUID,
        bakedAt: Date,
        name: String,
        hydration: Double = 75
    ) -> Bake {
        Bake(
            id: id,
            userID: user,
            starterID: starter,
            bakedAt: bakedAt,
            name: name,
            doughHydrationPercent: hydration,
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

    private func sampleAnalysis(
        overall: Int,
        crumb: Int = 70,
        crust: Int = 70,
        spring: Int = 70
    ) -> LoafAIAnalysis {
        LoafAIAnalysis(
            crumbScore: crumb,
            crustScore: crust,
            ovenSpringScore: spring,
            overallScore: overall,
            strengths: ["Open crumb"],
            improvements: ["Steam"],
            nextSteps: ["Add steam"],
            summary: "Assessment",
            why: "Why"
        )
    }
}
