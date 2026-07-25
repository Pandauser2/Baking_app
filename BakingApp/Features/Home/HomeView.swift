import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager

    @State private var isShowingPaywall = false
    @State private var showStarterWorkflow = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Baking App")
                    .font(.largeTitle)
                    .bold()

                Group {
                    switch authManager.status {
                    case .signedIn(let session):
                        Text("Signed in: \(session.email ?? session.userID.uuidString)")
                    case .signedOut:
                        Text("Signed out")
                    case .loadingSession:
                        Text("Restoring session...")
                    case .error(let message):
                        Text("Auth error: \(message)")
                    }
                }

                Text("Subscription: \(billingManager.hasProEntitlement ? "Pro active" : "Free")")
                    .font(.headline)

                Button("Open Paywall") {
                    isShowingPaywall = true
                }
                .buttonStyle(.borderedProminent)

                Button("Starter Workflow") {
                    showStarterWorkflow = true
                }
                .buttonStyle(.borderedProminent)

                Text("Loaf analysis is hidden from Home until Phase C.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Refresh Entitlement") {
                    Task { await billingManager.refreshEntitlement() }
                }
                .buttonStyle(.bordered)

                Button("Sign Out") {
                    Task { await authManager.signOut() }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)

                Spacer()
            }
            .padding()
            .navigationTitle("Home")
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .navigationDestination(isPresented: $showStarterWorkflow) {
                StarterListView(
                    viewModel: StarterWorkflowViewModel(
                        repository: environment.starterRepository,
                        analytics: environment.analytics,
                        isProUser: billingManager.hasProEntitlement
                    )
                )
            }
        }
    }
}

