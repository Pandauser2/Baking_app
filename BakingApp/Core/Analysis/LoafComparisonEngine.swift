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

    static func classifyScoreDelta(current: Int, previous: Int) -> ComparisonTrend {
        let delta = current - previous
        if abs(delta) <= LoafComparisonThresholds.scorePoints {
            return .unchanged
        }
        return delta > 0 ? .improved : .regressed
    }

    static func classifyHydrationDelta(current: Double, previous: Double) -> ComparisonTrend {
        classifyMagnitude(
            current: current,
            previous: previous,
            unchangedWithin: LoafComparisonThresholds.hydrationPercent,
            higherIsImproved: false
        )
    }

    /// Process timing / temperature: direction is informational only (not quality).
    /// We still label higher/lower using improved/regressed as "increased"/"decreased" semantics
    /// via trend: improved = increased, regressed = decreased for display mapping in UI.
    static func classifyNumericDelta(
        current: Double,
        previous: Double,
        unchangedWithin: Double
    ) -> ComparisonTrend {
        let delta = current - previous
        if abs(delta) <= unchangedWithin {
            return .unchanged
        }
        return delta > 0 ? .improved : .regressed
    }

    private static func classifyMagnitude(
        current: Double,
        previous: Double,
        unchangedWithin: Double,
        higherIsImproved: Bool
    ) -> ComparisonTrend {
        let delta = current - previous
        if abs(delta) <= unchangedWithin {
            return .unchanged
        }
        let increased = delta > 0
        if higherIsImproved {
            return increased ? .improved : .regressed
        }
        return increased ? .improved : .regressed
    }

    static func buildPresentation(
        currentBake: Bake,
        currentAnalysis: LoafAIAnalysis,
        previous: PreviousBakeRef?,
        previousAnalysis: CanonicalLoafAnalysis?,
        why: String,
        recommendation: String
    ) -> LoafComparisonPresentation {
        let selectedMode = mode(previous: previous, previousAnalysis: previousAnalysis)
        let scores = LoafScoreSnapshot(analysis: currentAnalysis)
        let processDeltas: [DimensionDelta]
        let scoreDeltas: [DimensionDelta]

        switch selectedMode {
        case .baseline:
            processDeltas = []
            scoreDeltas = []
        case .processComparison:
            processDeltas = makeProcessDeltas(
                current: BakeProcessSnapshot(bake: currentBake),
                previous: BakeProcessSnapshot(bake: previous!.bake)
            )
            scoreDeltas = []
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

        return LoafComparisonPresentation(
            mode: selectedMode,
            previousBakeID: previous?.bake.id,
            previousBakeName: previous?.bake.name,
            starterChanged: previous?.starterChanged ?? false,
            baselineMessage: selectedMode == .baseline ? baselineMessage : nil,
            visualComparisonUnavailableMessage: selectedMode == .processComparison
                ? visualUnavailableMessage
                : nil,
            scoreDeltas: scoreDeltas,
            processDeltas: processDeltas,
            assessment: currentAnalysis.summary,
            why: why,
            recommendation: recommendation,
            strengths: currentAnalysis.strengths,
            issues: currentAnalysis.improvements,
            scores: scores
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

    static func makeScoreDeltas(current: LoafScoreSnapshot, previous: LoafScoreSnapshot) -> [DimensionDelta] {
        [
            scoreDelta(label: "Crumb", current: current.crumbScore, previous: previous.crumbScore),
            scoreDelta(label: "Crust", current: current.crustScore, previous: previous.crustScore),
            scoreDelta(label: "Oven spring", current: current.ovenSpringScore, previous: previous.ovenSpringScore),
            scoreDelta(label: "Overall", current: current.overallScore, previous: previous.overallScore),
        ]
    }

    static func makeProcessDeltas(current: BakeProcessSnapshot, previous: BakeProcessSnapshot) -> [DimensionDelta] {
        var deltas: [DimensionDelta] = []
        deltas.append(
            processDelta(
                label: "Hydration",
                current: current.doughHydrationPercent,
                previous: previous.doughHydrationPercent,
                unit: "%",
                unchangedWithin: LoafComparisonThresholds.hydrationPercent,
                format: { String(format: "%.0f%%", $0) }
            )
        )
        deltas.append(
            processDelta(
                label: "Bulk fermentation",
                current: Double(current.bulkFermentationMinutes),
                previous: Double(previous.bulkFermentationMinutes),
                unit: "min",
                unchangedWithin: Double(LoafComparisonThresholds.minutes),
                format: { "\(Int($0)) min" }
            )
        )
        deltas.append(
            processDelta(
                label: "Final proof",
                current: Double(current.finalProofMinutes),
                previous: Double(previous.finalProofMinutes),
                unit: "min",
                unchangedWithin: Double(LoafComparisonThresholds.minutes),
                format: { "\(Int($0)) min" }
            )
        )
        if let currentTemp = current.fermentationTemperatureCelsius,
           let previousTemp = previous.fermentationTemperatureCelsius {
            deltas.append(
                processDelta(
                    label: "Fermentation temp",
                    current: currentTemp,
                    previous: previousTemp,
                    unit: "°C",
                    unchangedWithin: LoafComparisonThresholds.temperatureCelsius,
                    format: { String(format: "%.0f°C", $0) }
                )
            )
        }
        deltas.append(
            processDelta(
                label: "Oven temperature",
                current: current.ovenTemperatureCelsius,
                previous: previous.ovenTemperatureCelsius,
                unit: "°C",
                unchangedWithin: LoafComparisonThresholds.temperatureCelsius,
                format: { String(format: "%.0f°C", $0) }
            )
        )
        deltas.append(
            processDelta(
                label: "Bake time",
                current: Double(current.bakingTimeMinutes),
                previous: Double(previous.bakingTimeMinutes),
                unit: "min",
                unchangedWithin: Double(LoafComparisonThresholds.minutes),
                format: { "\(Int($0)) min" }
            )
        )
        return deltas
    }

    private static func scoreDelta(label: String, current: Int, previous: Int) -> DimensionDelta {
        let trend = classifyScoreDelta(current: current, previous: previous)
        let delta = current - previous
        let deltaDisplay: String?
        if trend == .unchanged {
            deltaDisplay = nil
        } else {
            deltaDisplay = delta > 0 ? "+\(delta)" : "\(delta)"
        }
        return DimensionDelta(
            label: label,
            previousDisplay: "\(previous)",
            currentDisplay: "\(current)",
            trend: trend,
            deltaDisplay: deltaDisplay
        )
    }

    private static func processDelta(
        label: String,
        current: Double,
        previous: Double,
        unit: String,
        unchangedWithin: Double,
        format: (Double) -> String
    ) -> DimensionDelta {
        let trend = classifyNumericDelta(
            current: current,
            previous: previous,
            unchangedWithin: unchangedWithin
        )
        let delta = current - previous
        let deltaDisplay: String?
        if trend == .unchanged {
            deltaDisplay = nil
        } else if unit == "%" {
            deltaDisplay = String(format: "%+.0f%%", delta)
        } else if unit == "°C" {
            deltaDisplay = String(format: "%+.0f°C", delta)
        } else {
            deltaDisplay = String(format: "%+.0f %@", delta, unit)
        }
        return DimensionDelta(
            label: label,
            previousDisplay: format(previous),
            currentDisplay: format(current),
            trend: trend,
            deltaDisplay: deltaDisplay
        )
    }
}
