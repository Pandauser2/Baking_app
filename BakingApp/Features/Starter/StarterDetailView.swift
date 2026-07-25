import SwiftUI

struct StarterDetailView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager
    @EnvironmentObject private var environment: AppEnvironment

    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    var body: some View {
        List {
            Section("Profile") {
                Text(starter.name)
                    .font(.headline)
                if let hydration = starter.hydrationPreference {
                    Text("Hydration preference: \(Int(hydration))%")
                }
                Text(starter.active ? "Active starter" : "Inactive starter")
                    .foregroundStyle(starter.active ? .green : .secondary)
            }

            Section("Current State") {
                if let state = viewModel.starterState {
                    Text(state.stateLabel.capitalized)
                    Text("Updated: \(state.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No inferred state yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Workflow") {
                NavigationLink("Log Feeding") {
                    FeedingLogCreateView(starter: starter, viewModel: viewModel)
                }
                NavigationLink("Feeding History") {
                    FeedingHistoryView(starter: starter, viewModel: viewModel)
                }
                NavigationLink("Scan Starter") {
                    StarterScanView(starter: starter, viewModel: viewModel)
                }
                NavigationLink("Timeline") {
                    StarterTimelineView(starter: starter, viewModel: viewModel)
                }
            }

            Section("Phase C") {
                Text("Loaf analysis is unavailable in Home until Phase C.")
                    .foregroundStyle(.secondary)
            }

            if !billingManager.hasProEntitlement {
                Section {
                    Button("Upgrade to Pro") {
                        environment.analytics.track(.paywallViewed)
                    }
                }
            }
        }
        .navigationTitle(starter.name)
        .task {
            await viewModel.loadStarterState(starterID: starter.id)
            await viewModel.loadTimeline(starterID: starter.id)
            if case .signedIn = authManager.status {
                await viewModel.loadFeedingHistory(starterID: starter.id)
            }
        }
    }
}

