import SwiftUI

struct StarterTimelineView: View {
    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    var body: some View {
        List {
            if viewModel.timeline.isEmpty {
                VStack(spacing: 8) {
                    Text("No starter scans yet.")
                        .font(.headline)
                    Text("Your saved analyses will appear here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.timeline) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        if let analysis = item.analysis {
                            Text(analysis.renderedExplanation)
                                .font(.subheadline)
                        }
                        if let recommendation = item.recommendation {
                            Text("Recommendation: \(recommendation.recommendation)")
                                .font(.caption)
                            Text("Outcome: \(recommendation.outcome.replacingOccurrences(of: "_", with: " ").capitalized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Starter Timeline")
        .task {
            await viewModel.loadTimeline(starterID: starter.id)
        }
    }
}

