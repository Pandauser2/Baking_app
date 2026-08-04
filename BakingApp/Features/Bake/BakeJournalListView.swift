import SwiftUI

struct BakeJournalListView: View {
    @EnvironmentObject private var router: HomeNavigationRouter
    @ObservedObject var viewModel: BakeJournalViewModel

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView("Loading bake journal...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                VStack(spacing: 12) {
                    Image(systemName: "flame")
                        .imageScale(.large)
                    Text("No bakes yet")
                        .font(.headline)
                    Text("Log your first bake to start building loaf history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeJournalEmpty)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            case .loaded:
                List(viewModel.bakes) { bake in
                    Button {
                        router.push(.bakeDetail(bake.id), screen: "BakeJournal")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bake.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(bake.bakedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Rating \(bake.resultRating)/5 · \(Int(bake.doughHydrationPercent))% hydration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("bake.journal.row.\(bake.id.uuidString.lowercased())")
                }
            }
        }
        .navigationTitle("Bake Journal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") {
                    router.push(.bakeCreate, screen: "BakeJournal")
                }
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeJournalAdd)
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}
