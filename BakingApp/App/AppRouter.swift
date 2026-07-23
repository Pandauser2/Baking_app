import Foundation

enum AppRoute: Equatable {
    case loading
    case authentication
    case onboarding
    case home
}

struct AppRouter {
    static func route(for authStatus: AuthStatus, onboardingCompleted: Bool) -> AppRoute {
        switch authStatus {
        case .loadingSession:
            return .loading
        case .signedOut, .error:
            return .authentication
        case .signedIn:
            return onboardingCompleted ? .home : .onboarding
        }
    }
}

