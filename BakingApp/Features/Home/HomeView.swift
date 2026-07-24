import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager

    @State private var isShowingPaywall = false
    @State private var showAnalysis = false

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

                Button("Analyze Loaf") {
                    if billingManager.hasProEntitlement {
                        showAnalysis = true
                    } else {
                        isShowingPaywall = true
                    }
                }
                .buttonStyle(.borderedProminent)

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
            .navigationDestination(isPresented: $showAnalysis) {
                AnalysisView(
                    viewModel: AnalysisViewModel(
                        repository: environment.loafAnalysisRepository,
                        analytics: environment.analytics
                    )
                )
            }
        }
    }
}

