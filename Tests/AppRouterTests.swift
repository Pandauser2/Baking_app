import XCTest
@testable import BakingApp

final class AppRouterTests: XCTestCase {
    func testLoadingRoute() {
        XCTAssertEqual(AppRouter.route(for: .loadingSession, onboardingCompleted: false), .loading)
    }

    func testAuthRouteWhenSignedOut() {
        XCTAssertEqual(AppRouter.route(for: .signedOut, onboardingCompleted: false), .authentication)
    }

    func testOnboardingRouteWhenSignedInAndNotCompleted() {
        let session = UserSession(userID: UUID(), email: "a@b.com")
        XCTAssertEqual(AppRouter.route(for: .signedIn(session), onboardingCompleted: false), .onboarding)
    }

    func testHomeRouteWhenSignedInAndCompleted() {
        let session = UserSession(userID: UUID(), email: "a@b.com")
        XCTAssertEqual(AppRouter.route(for: .signedIn(session), onboardingCompleted: true), .home)
    }
}

