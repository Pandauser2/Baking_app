import SwiftUI

struct StarterDetailView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var router: HomeNavigationRouter

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
                Button("Log Feeding") {
                    router.push(.feedingLog(starter.id), screen: "StarterDetail")
                }
                .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowLogFeeding)

                Button("Feeding History") {
                    router.push(.feedingHistory(starter.id), screen: "StarterDetail")
                }
                .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowFeedingHistory)

                Button("Scan Starter") {
                    router.push(.scanStarter(starter.id), screen: "StarterDetail")
                }
                .accessibilityIdentifier(HomeNavigationAccessibilityID.workflowScanStarter)

                Button("Timeline") {
                    router.push(.timeline(starter.id), screen: "StarterDetail")
                }
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
