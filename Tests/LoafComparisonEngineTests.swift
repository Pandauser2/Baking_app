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

    func testScoreThresholdsPlusMinusFourUnchangedPlusMinusFiveBoundary() {
        // ±4 → unchanged
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 74, previous: 70), .unchanged)
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 66, previous: 70), .unchanged)
        // +5 → improved, -5 → regressed
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 75, previous: 70), .improved)
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 65, previous: 70), .regressed)
        // +10 still improved
        XCTAssertEqual(LoafComparisonEngine.classifyScoreDelta(current: 80, previous: 70), .improved)
    }

    func testProcessValuesUseIncreasedDecreasedNeverImprovedRegressed() {
        XCTAssertEqual(
            LoafComparisonEngine.classifyProcessDelta(current: 78, previous: 70, unchangedWithin: 1),
            .increased
        )
        XCTAssertEqual(
            LoafComparisonEngine.classifyProcessDelta(current: 60, previous: 70, unchangedWithin: 1),
            .decreased
        )
        XCTAssertEqual(
            LoafComparisonEngine.classifyProcessDelta(current: 70.5, previous: 70, unchangedWithin: 1),
            .unchanged
        )
        let previousBake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A", hydration: 70)
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "B", hydration: 78)
        let deltas = LoafComparisonEngine.makeProcessDeltas(
            current: BakeProcessSnapshot(bake: current),
            previous: BakeProcessSnapshot(bake: previousBake)
        )
        let hydration = deltas.first { $0.dimension == "hydration" }
        XCTAssertEqual(hydration?.change, .increased)
        // ProcessChangeDirection raw values must never be score labels.
        for delta in deltas {
            XCTAssertFalse(delta.change.rawValue == "improved")
            XCTAssertFalse(delta.change.rawValue == "regressed")
        }
    }

    func testBaselineSnapshotPersistedShape() {
        let bake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "First")
        let analysis = sampleAnalysis(overall: 70)
        let snapshot = LoafComparisonEngine.buildSnapshot(
            currentBake: bake,
            currentAnalysis: analysis,
            previous: nil,
            previousAnalysis: nil,
            recommendation: "Keep hydration"
        )
        XCTAssertEqual(snapshot.comparisonMode, .baseline)
        XCTAssertNil(snapshot.previousBakeID)
        XCTAssertNil(snapshot.previousStarterID)
        XCTAssertEqual(snapshot.starterChanged, false)
        XCTAssertTrue(snapshot.scoreDeltas.isEmpty)
        XCTAssertTrue(snapshot.processDeltas.isEmpty)
        XCTAssertEqual(snapshot.recommendation, "Keep hydration")

        let encoded = try! JSONEncoder().encode(analysis.encodingWithComparison(snapshot))
        let decoded = try! JSONDecoder().decode(LoafAIAnalysis.self, from: encoded)
        XCTAssertEqual(decoded.comparison, snapshot)
        XCTAssertEqual(decoded.comparison?.comparisonMode, .baseline)
        XCTAssertNil(decoded.comparison?.previousBakeID)
    }

    func testFullComparisonPreviousBakeIDPersistedAndReloadIdentical() {
        let previousBake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A", hydration: 70)
        let current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "B", hydration: 78)
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
        let currentAnalysis = sampleAnalysis(overall: 80, crumb: 75, crust: 70, spring: 65)
        let snapshot = LoafComparisonEngine.buildSnapshot(
            currentBake: current,
            currentAnalysis: currentAnalysis,
            previous: PreviousBakeRef(bake: previousBake, starterChanged: false),
            previousAnalysis: previousAnalysis,
            recommendation: "Add steam"
        )
        XCTAssertEqual(snapshot.comparisonMode, .fullComparison)
        XCTAssertEqual(snapshot.previousBakeID, previousBake.id)
        XCTAssertEqual(snapshot.previousStarterID, starterA)
        XCTAssertEqual(snapshot.starterChanged, false)
        XCTAssertFalse(snapshot.scoreDeltas.isEmpty)
        XCTAssertFalse(snapshot.processDeltas.isEmpty)

        let overall = snapshot.scoreDeltas.first { $0.dimension == "overall" }
        XCTAssertEqual(overall?.delta, 10)
        XCTAssertEqual(overall?.classification, .improved)
        let crumb = snapshot.scoreDeltas.first { $0.dimension == "crumb" }
        XCTAssertEqual(crumb?.delta, 5)
        XCTAssertEqual(crumb?.classification, .improved)
        let crust = snapshot.scoreDeltas.first { $0.dimension == "crust" }
        XCTAssertEqual(crust?.classification, .unchanged)
        let spring = snapshot.scoreDeltas.first { $0.dimension == "oven_spring" }
        XCTAssertEqual(spring?.classification, .regressed)
        let hydration = snapshot.processDeltas.first { $0.dimension == "hydration" }
        XCTAssertEqual(hydration?.change, .increased)

        let withComparison = currentAnalysis.encodingWithComparison(snapshot)
        let encoded = try! JSONEncoder().encode(withComparison)
        let decoded = try! JSONDecoder().decode(LoafAIAnalysis.self, from: encoded)
        XCTAssertEqual(decoded.comparison, snapshot)

        let reloaded = LoafComparisonEngine.presentation(
            from: decoded.comparison!,
            analysis: decoded,
            previousBakeName: "A"
        )
        XCTAssertEqual(reloaded.snapshot, snapshot)
        XCTAssertEqual(reloaded.previousBakeID, previousBake.id)
        XCTAssertEqual(reloaded.mode, .fullComparison)
    }

    func testModifyingBakeJournalAfterScanDoesNotAlterHistoricalComparison() {
        let previousBake = makeBake(id: UUID(), starter: starterA, bakedAt: date(1), name: "A", hydration: 70)
        var current = makeBake(id: UUID(), starter: starterA, bakedAt: date(2), name: "B", hydration: 78)
        let previousAnalysis = CanonicalLoafAnalysis(
            scanID: UUID(),
            analysisID: UUID(),
            bakeID: previousBake.id,
            storagePath: "a.jpg",
            model: "t",
            promptVersion: "v1",
            confidence: 0.7,
            analysis: sampleAnalysis(overall: 70),
            renderedExplanation: "prev",
            createdAt: date(1)
        )
        let analysis = sampleAnalysis(overall: 80)
        let savedSnapshot = LoafComparisonEngine.buildSnapshot(
            currentBake: current,
            currentAnalysis: analysis,
            previous: PreviousBakeRef(bake: previousBake, starterChanged: false),
            previousAnalysis: previousAnalysis,
            recommendation: "Add steam"
        )
        let persisted = analysis.encodingWithComparison(savedSnapshot)

        // Simulate user editing journal hydration after the scan was saved.
        current = makeBake(
            id: current.id,
            starter: starterA,
            bakedAt: current.bakedAt,
            name: current.name,
            hydration: 90
        )
        let liveRecompute = LoafComparisonEngine.buildSnapshot(
            currentBake: current,
            currentAnalysis: analysis,
            previous: PreviousBakeRef(bake: previousBake, starterChanged: false),
            previousAnalysis: previousAnalysis,
            recommendation: "Add steam"
        )
        XCTAssertNotEqual(
            liveRecompute.processDeltas.first { $0.dimension == "hydration" }?.current,
            savedSnapshot.processDeltas.first { $0.dimension == "hydration" }?.current
        )

        // Historical UI must use persisted snapshot, not live recompute.
        let historical = LoafComparisonEngine.presentation(
            from: persisted.comparison!,
            analysis: persisted,
            previousBakeName: "A"
        )
        XCTAssertEqual(historical.snapshot, savedSnapshot)
        XCTAssertEqual(
            historical.processDeltas.first { $0.dimension == "hydration" }?.current,
            78
        )
        XCTAssertEqual(
            historical.processDeltas.first { $0.dimension == "hydration" }?.change,
            .increased
        )
    }

    func testBaselineModePresentation() {
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
        XCTAssertNil(presentation.snapshot.previousBakeID)
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
        XCTAssertEqual(
            presentation.processDeltas.first { $0.dimension == "hydration" }?.change,
            .increased
        )
    }

    func testMissingOptionalFermentationTempSkipped() {
        let previous = BakeProcessSnapshot(
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
        XCTAssertFalse(deltas.contains { $0.dimension == "fermentation_temperature" })
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
