import SwiftUI

struct BakeDetailView: View {
    @ObservedObject var viewModel: BakeJournalViewModel
    let bakeID: UUID

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
        .task {
            await viewModel.selectBake(id: bakeID)
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
