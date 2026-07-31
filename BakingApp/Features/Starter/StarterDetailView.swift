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
                NavigationLink("Log Feeding", value: HomeNavigationRoute.feedingLog(starter.id))
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowLogFeeding)
                NavigationLink("Feeding History", value: HomeNavigationRoute.feedingHistory(starter.id))
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowFeedingHistory)
                NavigationLink("Scan Starter", value: HomeNavigationRoute.scanStarter(starter.id))
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowScanStarter)
                NavigationLink("Timeline", value: HomeNavigationRoute.timeline(starter.id))
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowTimeline)
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
        .accessibilityIdentifier(HomeNavigationAccessibilityID.starterDetailRoot)
        .task {
            await viewModel.loadStarterState(starterID: starter.id)
            await viewModel.loadTimeline(starterID: starter.id)
            if case .signedIn = authManager.status {
                await viewModel.loadFeedingHistory(starterID: starter.id)
            }
        }
    }
}
