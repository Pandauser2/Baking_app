import SwiftUI

struct FeedingHistoryView: View {
    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    var body: some View {
        List {
            if viewModel.feedingLogs.isEmpty {
                VStack(spacing: 8) {
                    Text("No feeding logs yet.")
                        .font(.headline)
                    Text("Log a feeding to build starter memory.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.feedingLogs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(log.roomTempC, specifier: "%.1f")°C")
                            .font(.headline)
                        Text(log.loggedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Flour: \(log.flourG ?? 0)g · Water: \(log.waterG ?? 0)g · Starter: \(log.starterG ?? 0)g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let notes = log.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Feeding History")
        .task {
            await viewModel.loadFeedingHistory(starterID: starter.id)
        }
    }
}

