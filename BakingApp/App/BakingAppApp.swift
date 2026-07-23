import SwiftUI

@main
struct BakingAppApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.authManager)
                .environmentObject(environment.billingManager)
                .environmentObject(environment.onboardingStore)
                .task {
                    await environment.authManager.restoreSession()
                    await environment.billingManager.refreshEntitlement()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var onboardingStore: OnboardingStore

    var body: some View {
        let route = AppRouter.route(for: authManager.status, onboardingCompleted: onboardingStore.isCompleted)

        switch route {
        case .loading:
            ProgressView("Restoring session...")
        case .authentication:
            AuthenticationView()
        case .onboarding:
            OnboardingView {
                environment.analytics.track(.onboardingCompleted)
                onboardingStore.complete()
            }
        case .home:
            HomeView()
        }
    }
}

