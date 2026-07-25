import SwiftUI

struct StarterAnalysisResultView: View {
    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let response = viewModel.pendingAIResponse {
                    Group {
                        Text("Observations")
                            .font(.headline)
                        ForEach(response.observations, id: \.self) { observation in
                            Text("• \(observation)")
                        }
                    }
                    Group {
                        Text("Inferred Starter State")
                            .font(.headline)
                        Text(response.starterState.capitalized)
                        Text("Confidence: \(response.confidence, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        Text("Why")
                            .font(.headline)
                        Text(response.humanExplanation)
                    }
                    Group {
                        Text("Compared to previous")
                            .font(.headline)
                        Text(response.compareToPrevious.explanation)
                    }

                    if viewModel.persistedIDs == nil {
                        Button("Save Analysis") {
                            Task { await viewModel.savePendingAnalysis(starterID: starter.id) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if let recommendation = viewModel.recommendation {
                        RecommendationCardView(recommendation: recommendation) { outcome in
                            Task { await viewModel.markRecommendationOutcome(outcome) }
                        }
                    }
                } else {
                    Text("No analysis result available.")
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
    }
}

