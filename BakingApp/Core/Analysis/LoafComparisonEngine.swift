import Foundation

enum PreviousBakeSelector {
    /// Latest bake strictly before `current` by `baked_at` (then `created_at` as tie-break).
    /// Prefer same `starter_id`; otherwise latest prior bake with `starterChanged = true`.
    /// Never returns `current` or a future bake.
    static func select(current: Bake, from candidates: [Bake]) -> PreviousBakeRef? {
        let prior = candidates.filter { bake in
            bake.id != current.id
                && bake.bakedAt < current.bakedAt
        }
        .sorted { lhs, rhs in
            if lhs.bakedAt != rhs.bakedAt {
                return lhs.bakedAt > rhs.bakedAt
            }
            return lhs.createdAt > rhs.createdAt
        }

        guard !prior.isEmpty else { return nil }

        if let sameStarter = prior.first(where: { $0.starterID == current.starterID }) {
            return PreviousBakeRef(bake: sameStarter, starterChanged: false)
        }

        guard let fallback = prior.first else { return nil }
        return PreviousBakeRef(bake: fallback, starterChanged: true)
    }
}

enum LoafComparisonEngine {
    static let baselineMessage =
        "This is your first recorded loaf. We’ll use it as the baseline for your next comparison."
    static let visualUnavailableMessage =
        "Visual loaf comparison is unavailable because the previous bake has no loaf scan yet. Showing process changes from your journal."

    static func mode(
        previous: PreviousBakeRef?,
        previousAnalysis: CanonicalLoafAnalysis?
    ) -> LoafComparisonMode {
        guard previous != nil else { return .baseline }
        guard previousAnalysis != nil else { return .processComparison }
        return .fullComparison
    }

    /// delta >= +5 → improved; delta <= -5 → regressed; otherwise unchanged.
    static func classifyScoreDelta(current: Int, previous: Int) -> ScoreClassification {
        let delta = current - previous
        if delta >= LoafComparisonThresholds.scorePoints {
            return .improved
        }
        if delta <= -LoafComparisonThresholds.scorePoints {
            return .regressed
        }
        return .unchanged
    }

    static func classifyProcessDelta(
        current: Double,
        previous: Double,
        unchangedWithin: Double
    ) -> ProcessChangeDirection {
        let delta = current - previous
        if abs(delta) <= unchangedWithin {
            return .unchanged
        }
        return delta > 0 ? .increased : .decreased
    }

    static func buildSnapshot(
        currentBake: Bake,
        currentAnalysis: LoafAIAnalysis,
        previous: PreviousBakeRef?,
        previousAnalysis: CanonicalLoafAnalysis?,
        recommendation: String
    ) -> LoafComparisonSnapshot {
        let selectedMode = mode(previous: previous, previousAnalysis: previousAnalysis)
        let scores = LoafScoreSnapshot(analysis: currentAnalysis)
        let scoreDeltas: [ScoreDeltaSnapshot]
        let processDeltas: [ProcessDeltaSnapshot]

        switch selectedMode {
        case .baseline:
            scoreDeltas = []
            processDeltas = []
        case .processComparison:
            scoreDeltas = []
            processDeltas = makeProcessDeltas(
                current: BakeProcessSnapshot(bake: currentBake),
                previous: BakeProcessSnapshot(bake: previous!.bake)
            )
        case .fullComparison:
            processDeltas = makeProcessDeltas(
                current: BakeProcessSnapshot(bake: currentBake),
                previous: BakeProcessSnapshot(bake: previous!.bake)
            )
            scoreDeltas = makeScoreDeltas(
                current: scores,
                previous: LoafScoreSnapshot(analysis: previousAnalysis!.analysis)
            )
        }

        return LoafComparisonSnapshot(
            comparisonMode: selectedMode,
            previousBakeID: previous?.bake.id,
            previousStarterID: previous?.bake.starterID,
            starterChanged: previous?.starterChanged ?? false,
            scoreDeltas: scoreDeltas,
            processDeltas: processDeltas,
            recommendation: recommendation
        )
    }

    static func presentation(
        from snapshot: LoafComparisonSnapshot,
        analysis: LoafAIAnalysis,
        previousBakeName: String?
    ) -> LoafComparisonPresentation {
        LoafComparisonPresentation(
            mode: snapshot.comparisonMode,
            previousBakeID: snapshot.previousBakeID,
            previousBakeName: previousBakeName,
            previousStarterID: snapshot.previousStarterID,
            starterChanged: snapshot.starterChanged,
            baselineMessage: snapshot.comparisonMode == .baseline ? baselineMessage : nil,
            visualComparisonUnavailableMessage: snapshot.comparisonMode == .processComparison
                ? visualUnavailableMessage
                : nil,
            scoreDeltas: snapshot.scoreDeltas,
            processDeltas: snapshot.processDeltas,
            assessment: analysis.summary,
            why: analysis.why,
            recommendation: snapshot.recommendation.isEmpty ? analysis.recommendation : snapshot.recommendation,
            strengths: analysis.strengths,
            issues: analysis.improvements,
            scores: LoafScoreSnapshot(analysis: analysis),
            snapshot: snapshot
        )
    }

    static func buildPresentation(
        currentBake: Bake,
        currentAnalysis: LoafAIAnalysis,
        previous: PreviousBakeRef?,
        previousAnalysis: CanonicalLoafAnalysis?,
        why: String,
        recommendation: String
    ) -> LoafComparisonPresentation {
        let snapshot = buildSnapshot(
            currentBake: currentBake,
            currentAnalysis: currentAnalysis,
            previous: previous,
            previousAnalysis: previousAnalysis,
            recommendation: recommendation
        )
        // Keep why on analysis for display; snapshot owns recommendation + deltas.
        let analysis = LoafAIAnalysis(
            crumbScore: currentAnalysis.crumbScore,
            crustScore: currentAnalysis.crustScore,
            ovenSpringScore: currentAnalysis.ovenSpringScore,
            overallScore: currentAnalysis.overallScore,
            strengths: currentAnalysis.strengths,
            improvements: currentAnalysis.improvements,
            nextSteps: currentAnalysis.nextSteps,
            summary: currentAnalysis.summary,
            why: why.isEmpty ? currentAnalysis.why : why,
            comparison: snapshot
        )
        return presentation(
            from: snapshot,
            analysis: analysis,
            previousBakeName: previous?.bake.name
        )
    }

    static func makeAnalyzeContext(
        currentBake: Bake,
        previous: PreviousBakeRef?,
        previousAnalysis: CanonicalLoafAnalysis?
    ) -> LoafAnalyzeContext {
        let selectedMode = mode(previous: previous, previousAnalysis: previousAnalysis)
        return LoafAnalyzeContext(
            comparisonMode: selectedMode,
            currentProcess: BakeProcessSnapshot(bake: currentBake),
            previousBakeID: previous?.bake.id,
            previousBakeName: previous?.bake.name,
            starterChanged: previous?.starterChanged ?? false,
            previousProcess: previous.map { BakeProcessSnapshot(bake: $0.bake) },
            previousScores: previousAnalysis.map { LoafScoreSnapshot(analysis: $0.analysis) }
        )
    }

    static func makeScoreDeltas(current: LoafScoreSnapshot, previous: LoafScoreSnapshot) -> [ScoreDeltaSnapshot] {
        [
            scoreDelta(dimension: "crumb", current: current.crumbScore, previous: previous.crumbScore),
            scoreDelta(dimension: "crust", current: current.crustScore, previous: previous.crustScore),
            scoreDelta(dimension: "oven_spring", current: current.ovenSpringScore, previous: previous.ovenSpringScore),
            scoreDelta(dimension: "overall", current: current.overallScore, previous: previous.overallScore),
        ]
    }

    static func makeProcessDeltas(current: BakeProcessSnapshot, previous: BakeProcessSnapshot) -> [ProcessDeltaSnapshot] {
        var deltas: [ProcessDeltaSnapshot] = []
        deltas.append(
            processDelta(
                dimension: "hydration",
                current: current.doughHydrationPercent,
                previous: previous.doughHydrationPercent,
                unchangedWithin: LoafComparisonThresholds.hydrationPercent
            )
        )
        deltas.append(
            processDelta(
                dimension: "bulk_fermentation",
                current: Double(current.bulkFermentationMinutes),
                previous: Double(previous.bulkFermentationMinutes),
                unchangedWithin: Double(LoafComparisonThresholds.minutes)
            )
        )
        deltas.append(
            processDelta(
                dimension: "final_proof",
                current: Double(current.finalProofMinutes),
                previous: Double(previous.finalProofMinutes),
                unchangedWithin: Double(LoafComparisonThresholds.minutes)
            )
        )
        if let currentTemp = current.fermentationTemperatureCelsius,
           let previousTemp = previous.fermentationTemperatureCelsius {
            deltas.append(
                processDelta(
                    dimension: "fermentation_temperature",
                    current: currentTemp,
                    previous: previousTemp,
                    unchangedWithin: LoafComparisonThresholds.temperatureCelsius
                )
            )
        }
        deltas.append(
            processDelta(
                dimension: "oven_temperature",
                current: current.ovenTemperatureCelsius,
                previous: previous.ovenTemperatureCelsius,
                unchangedWithin: LoafComparisonThresholds.temperatureCelsius
            )
        )
        deltas.append(
            processDelta(
                dimension: "bake_time",
                current: Double(current.bakingTimeMinutes),
                previous: Double(previous.bakingTimeMinutes),
                unchangedWithin: Double(LoafComparisonThresholds.minutes)
            )
        )
        return deltas
    }

    private static func scoreDelta(dimension: String, current: Int, previous: Int) -> ScoreDeltaSnapshot {
        ScoreDeltaSnapshot(
            dimension: dimension,
            previous: previous,
            current: current,
            delta: current - previous,
            classification: classifyScoreDelta(current: current, previous: previous)
        )
    }

    private static func processDelta(
        dimension: String,
        current: Double,
        previous: Double,
        unchangedWithin: Double
    ) -> ProcessDeltaSnapshot {
        ProcessDeltaSnapshot(
            dimension: dimension,
            previous: previous,
            current: current,
            delta: current - previous,
            change: classifyProcessDelta(
                current: current,
                previous: previous,
                unchangedWithin: unchangedWithin
            )
        )
    }
}
