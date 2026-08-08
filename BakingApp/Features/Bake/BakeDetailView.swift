import SwiftUI

struct BakeDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var router: HomeNavigationRouter
    @ObservedObject var viewModel: BakeJournalViewModel
    let bakeID: UUID

    @State private var loafAnalyses: [CanonicalLoafAnalysis] = []
    @State private var comparisonSummary: String?

    var body: some View {
        Group {
            if let bake = viewModel.selectedBake, bake.id == bakeID {
                List {
                    Section("Basics") {
                        LabeledContent("Name", value: bake.name)
                        LabeledContent("Baked", value: bake.bakedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Rating", value: "\(bake.resultRating)/5")
                    }
                    Section("Dough & timing") {
                        LabeledContent("Hydration", value: "\(formatNumber(bake.doughHydrationPercent))%")
                        LabeledContent("Bulk fermentation", value: "\(bake.bulkFermentationMinutes) min")
                        LabeledContent("Final proof", value: "\(bake.finalProofMinutes) min")
                    }
                    Section("Process") {
                        LabeledContent("Mixing", value: bake.mixingMethod)
                        LabeledContent("Shaping", value: bake.shapingMethod)
                    }
                    Section("Bake") {
                        LabeledContent("Oven", value: "\(formatNumber(bake.ovenTemperatureCelsius))°C")
                        LabeledContent("Bake time", value: "\(bake.bakingTimeMinutes) min")
                    }
                    if hasOptionalDetails(bake) {
                        Section("More details") {
                            if let temp = bake.fermentationTemperatureCelsius,
                               let source = bake.fermentationTemperatureSource {
                                LabeledContent(
                                    "Fermentation temp",
                                    value: "\(formatNumber(temp))°C (\(source.rawValue))"
                                )
                            }
                            if let retardation = bake.retardationMinutes {
                                LabeledContent("Retardation", value: "\(retardation) min")
                            }
                            if let folds = bake.numberOfFolds {
                                LabeledContent("Folds", value: "\(folds)")
                            }
                            if let steaming = bake.steamingMethod, !steaming.isEmpty {
                                LabeledContent("Steaming", value: steaming)
                            }
                            if let flourNotes = bake.flourNotes, !flourNotes.isEmpty {
                                Text(flourNotes)
                            }
                            if let notes = bake.notes, !notes.isEmpty {
                                Text(notes)
                            }
                        }
                    }

                    Section("Loaf scan") {
                        LabeledContent("Status", value: loafAnalyses.isEmpty ? "Not scanned" : "Analyzed")
                        if let comparisonSummary {
                            Text(comparisonSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("bake.detail.comparisonSummary")
                        }
                        if loafAnalyses.isEmpty {
                            Button("Scan loaf") {
                                router.push(.scanLoaf(bakeID), screen: "BakeDetail")
                            }
                            .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailScanLoaf)
                        } else {
                            Button("View loaf analysis") {
                                router.push(.loafAnalysisResult(bakeID), screen: "BakeDetail")
                            }
                            .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailViewAnalysis)
                            Button("Scan again") {
                                router.push(.scanLoaf(bakeID), screen: "BakeDetail")
                            }
                            .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailScanLoaf)
                        }
                    }
                }
            } else if viewModel.errorMessage != nil {
                VStack(spacing: 12) {
                    Text(viewModel.errorMessage ?? "Could not load bake.")
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.selectBake(id: bakeID) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView("Loading bake...")
            }
        }
        .navigationTitle("Bake Details")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !loafAnalyses.isEmpty {
                    Button("View analysis") {
                        router.push(.loafAnalysisResult(bakeID), screen: "BakeDetail")
                    }
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailViewAnalysis)
                }
                Button(loafAnalyses.isEmpty ? "Scan loaf" : "Scan again") {
                    router.push(.scanLoaf(bakeID), screen: "BakeDetail")
                }
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailScanLoaf)
            }
        }
        .task {
            await viewModel.selectBake(id: bakeID)
            await loadLoafState()
        }
        .onAppear {
            Task { await loadLoafState() }
        }
    }

    private func loadLoafState() async {
        do {
            let analyses = try await environment.loafAnalysisRepository.fetchLoafAnalyses(forBakeID: bakeID)
            loafAnalyses = analyses
            guard let latest = analyses.sorted(by: { $0.createdAt > $1.createdAt }).first else {
                comparisonSummary = nil
                return
            }
            let bake: Bake
            if let selected = viewModel.selectedBake {
                bake = selected
            } else {
                bake = try await environment.bakeRepository.fetchBake(bakeID: bakeID)
            }
            let allBakes = try await environment.bakeRepository.listBakes()
            let previous = PreviousBakeSelector.select(current: bake, from: allBakes)
            var previousAnalysis: CanonicalLoafAnalysis?
            if let previous {
                previousAnalysis = try await environment.loafAnalysisRepository
                    .fetchLoafAnalyses(forBakeID: previous.bake.id)
                    .sorted { $0.createdAt > $1.createdAt }
                    .first
            }
            let presentation = LoafComparisonEngine.buildPresentation(
                currentBake: bake,
                currentAnalysis: latest.analysis,
                previous: previous,
                previousAnalysis: previousAnalysis,
                why: latest.analysis.why,
                recommendation: latest.analysis.recommendation
            )
            switch presentation.mode {
            case .baseline:
                comparisonSummary = "Baseline loaf saved."
            case .processComparison:
                comparisonSummary = "Process comparison vs \(presentation.previousBakeName ?? "previous bake")."
            case .fullComparison:
                let improved = presentation.scoreDeltas.filter { $0.trend == .improved }.count
                let regressed = presentation.scoreDeltas.filter { $0.trend == .regressed }.count
                comparisonSummary = "Full comparison: \(improved) improved, \(regressed) regressed."
            }
        } catch {
            // Non-fatal: journal still shows.
        }
    }

    private func hasOptionalDetails(_ bake: Bake) -> Bool {
        bake.fermentationTemperatureCelsius != nil
            || bake.retardationMinutes != nil
            || bake.numberOfFolds != nil
            || !(bake.steamingMethod ?? "").isEmpty
            || !(bake.flourNotes ?? "").isEmpty
            || !(bake.notes ?? "").isEmpty
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
