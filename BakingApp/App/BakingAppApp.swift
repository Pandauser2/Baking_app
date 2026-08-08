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
                .onOpenURL { url in
                    Task {
                        await environment.authManager.handleAuthCallback(url)
                    }
                }
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
    @EnvironmentObject private var billingManager: BillingManager

    /// Stable owners — must not be recreated when auth/billing republish.
    @StateObject private var homeRouter = HomeNavigationRouter()
    @StateObject private var homeViewModelHolder = HomeViewModelHolder()
    @StateObject private var bakeJournalViewModelHolder = BakeJournalViewModelHolder()

    var body: some View {
        let route = AppRouter.route(for: authManager.status, onboardingCompleted: onboardingStore.isCompleted)

        Group {
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
                homeContent
            }
        }
        .alert("Authentication", isPresented: Binding(
            get: { authManager.infoMessage != nil },
            set: { _ in authManager.dismissInfoMessage() }
        )) {
            Button("OK", role: .cancel) {
                authManager.dismissInfoMessage()
            }
        } message: {
            Text(authManager.infoMessage ?? "")
        }
        .onChange(of: billingManager.hasProEntitlement) { isPro in
            homeViewModelHolder.updateProStatus(isPro)
        }
        .onChange(of: authManager.status) { status in
            if case .signedOut = status {
                homeRouter.popToRoot(screen: "signOut")
            }
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        let viewModel = homeViewModelHolder.viewModel(
            repository: environment.starterRepository,
            analytics: environment.analytics,
            isProUser: billingManager.hasProEntitlement
        )
        let bakeJournalViewModel = bakeJournalViewModelHolder.viewModel(
            bakeRepository: environment.bakeRepository,
            starterRepository: environment.starterRepository
        )
        HomeView(viewModel: viewModel, bakeJournalViewModel: bakeJournalViewModel)
            .environmentObject(homeRouter)
    }
}

/// Keeps a single `StarterWorkflowViewModel` alive across RootView refreshes.
@MainActor
final class HomeViewModelHolder: ObservableObject {
    private var viewModel: StarterWorkflowViewModel?

    func viewModel(
        repository: StarterRepository,
        analytics: AnalyticsTracking,
        isProUser: Bool
    ) -> StarterWorkflowViewModel {
        if let viewModel {
            return viewModel
        }
        let created = StarterWorkflowViewModel(
            repository: repository,
            analytics: analytics,
            isProUser: isProUser
        )
        viewModel = created
        return created
    }

    func updateProStatus(_ isPro: Bool) {
        viewModel?.updateProStatus(isPro)
    }
}
