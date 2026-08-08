import SwiftUI

struct AnalysisResultView: View {
    let result: LoafAnalyzeResult
    let imagePath: String?
    @ObservedObject var viewModel: AnalysisViewModel
    var onSaveBaseline: (() -> Void)?

    @State private var signedURL: URL?

    private var analysis: LoafAIAnalysis { result.analysis }
    private var comparison: LoafComparisonPresentation? { viewModel.comparison }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let signedURL {
                    AsyncImage(url: signedURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                sectionTitle("Overall assessment")
                Text(comparison?.assessment ?? analysis.summary)

                scoreRow("Overall", analysis.overallScore)
                scoreRow("Crumb", analysis.crumbScore)
                scoreRow("Crust", analysis.crustScore)
                scoreRow("Oven Spring", analysis.ovenSpringScore)

                comparisonSection

                if let comparison {
                    labeledList("Strengths", comparison.strengths)
                    labeledList("Issues", comparison.issues)

                    if !comparison.why.isEmpty {
                        sectionTitle("Why")
                        Text(comparison.why)
                    }

                    sectionTitle("Try this next")
                    Text(comparison.recommendation.isEmpty ? analysis.recommendation : comparison.recommendation)
                        .accessibilityIdentifier("loaf.result.recommendation")
                } else {
                    labeledList("Strengths", analysis.strengths)
                    labeledList("Issues", analysis.improvements)
                    sectionTitle("Try this next")
                    Text(analysis.recommendation)
                }

                if comparison?.mode == .baseline {
                    Button("Save as baseline") {
                        viewModel.saveAsBaseline()
                        onSaveBaseline?()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("loaf.result.saveBaseline")
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .accessibilityIdentifier(HomeNavigationAccessibilityID.loafAnalysisResultRoot)
        .task {
            if let imagePath {
                signedURL = await viewModel.signedImageURL(path: imagePath)
            }
        }
    }

    @ViewBuilder
    private var comparisonSection: some View {
        if let comparison {
            switch comparison.mode {
            case .baseline:
                sectionTitle("Compared with previous bake")
                Text(comparison.baselineMessage ?? LoafComparisonEngine.baselineMessage)
                    .accessibilityIdentifier("loaf.result.baselineMessage")
            case .processComparison:
                sectionTitle("Compared with previous bake")
                Text(comparedWithLine(comparison))
                if comparison.starterChanged {
                    Text("Note: previous bake used a different starter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(comparison.visualComparisonUnavailableMessage ?? LoafComparisonEngine.visualUnavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("loaf.result.visualUnavailable")
                processDeltasBlock(comparison.processDeltas)
            case .fullComparison:
                sectionTitle("Compared with previous bake")
                Text(comparedWithLine(comparison))
                if comparison.starterChanged {
                    Text("Note: previous bake used a different starter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                scoreDeltasBlock(comparison.scoreDeltas)
                if !comparison.processDeltas.isEmpty {
                    processDeltasBlock(comparison.processDeltas)
                }
            }
        }
    }

    private func comparedWithLine(_ comparison: LoafComparisonPresentation) -> String {
        if let name = comparison.previousBakeName {
            return "Compared with \(name)."
        }
        return "Compared with your previous bake."
    }

    private func scoreDeltasBlock(_ deltas: [ScoreDeltaSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Loaf quality")
            ForEach(deltas) { delta in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(delta.label).font(.subheadline.weight(.semibold))
                        Text("\(delta.previous) → \(delta.current)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(scoreLabel(delta.classification))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(scoreColor(delta.classification))
                }
                .accessibilityIdentifier("loaf.result.delta.\(delta.label)")
            }
        }
    }

    private func processDeltasBlock(_ deltas: [ProcessDeltaSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Process changes")
            ForEach(deltas) { delta in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(delta.label).font(.subheadline.weight(.semibold))
                        Text("\(formatProcess(delta.previous)) → \(formatProcess(delta.current))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(processLabel(delta.change))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(processColor(delta.change))
                }
                .accessibilityIdentifier("loaf.result.delta.\(delta.label)")
            }
        }
    }

    private func scoreLabel(_ classification: ScoreClassification) -> String {
        switch classification {
        case .improved: return "Improved"
        case .regressed: return "Regressed"
        case .unchanged: return "Unchanged"
        }
    }

    private func scoreColor(_ classification: ScoreClassification) -> Color {
        switch classification {
        case .improved: return .green
        case .regressed: return .orange
        case .unchanged: return .secondary
        }
    }

    private func processLabel(_ change: ProcessChangeDirection) -> String {
        switch change {
        case .increased: return "Increased"
        case .decreased: return "Decreased"
        case .unchanged: return "Unchanged"
        }
    }

    private func processColor(_ change: ProcessChangeDirection) -> Color {
        switch change {
        case .increased: return .blue
        case .decreased: return .purple
        case .unchanged: return .secondary
        }
    }

    private func formatProcess(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func scoreRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(String(value))
        }
    }

    private func labeledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            if items.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                }
            }
        }
    }
}
