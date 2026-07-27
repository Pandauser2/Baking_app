import XCTest
@testable import BakingApp

final class PaywallPresentationRulesTests: XCTestCase {
    func testDismissIsAvailableWhileLoading() {
        XCTAssertTrue(PaywallPresentationRules.canDismiss(for: .loading))
    }

    func testDismissIsAvailableOnFailure() {
        XCTAssertTrue(PaywallPresentationRules.canDismiss(for: .failure("Subscriptions unavailable")))
    }

    func testRetryVisibleOnFailure() {
        XCTAssertTrue(PaywallPresentationRules.showsRetry(for: .failure("Subscriptions unavailable")))
    }

    func testRetryHiddenForReadyState() {
        XCTAssertFalse(PaywallPresentationRules.showsRetry(for: .ready))
    }
}
