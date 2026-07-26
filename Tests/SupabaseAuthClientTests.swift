import XCTest
@testable import BakingApp

final class SupabaseAuthClientTests: XCTestCase {
    func testSignupRedirectURLIsExactExpectedCallback() {
        XCTAssertEqual(SupabaseAuthClient.callbackURL.absoluteString, "bakingapp://auth-callback")
    }
}
