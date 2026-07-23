import XCTest
@testable import BakingApp

@MainActor
final class AuthManagerTests: XCTestCase {
    func testRestoreSessionTransitionsToSignedIn() async {
        let expected = UserSession(userID: UUID(), email: "test@example.com")
        let client = FakeAuthClient(restoredSession: expected)
        let manager = AuthManager(client: client)

        await manager.restoreSession()

        XCTAssertEqual(manager.status, .signedIn(expected))
    }

    func testRestoreSessionTransitionsToSignedOutWhenNoSession() async {
        let client = FakeAuthClient(restoredSession: nil)
        let manager = AuthManager(client: client)

        await manager.restoreSession()

        XCTAssertEqual(manager.status, .signedOut)
    }

    func testSignInFailureTransitionsToError() async {
        let client = FakeAuthClient(signInError: AppError.authenticationFailed)
        let manager = AuthManager(client: client)

        await manager.signIn(email: "wrong@example.com", password: "bad")

        if case .error = manager.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected error status")
        }
    }
}

private struct FakeAuthClient: AuthClient {
    var restoredSession: UserSession?
    var signUpSession: UserSession = UserSession(userID: UUID(), email: "new@example.com")
    var signInSession: UserSession = UserSession(userID: UUID(), email: "in@example.com")
    var restoreError: Error?
    var signUpError: Error?
    var signInError: Error?
    var signOutError: Error?

    init(
        restoredSession: UserSession? = nil,
        restoreError: Error? = nil,
        signUpError: Error? = nil,
        signInError: Error? = nil,
        signOutError: Error? = nil
    ) {
        self.restoredSession = restoredSession
        self.restoreError = restoreError
        self.signUpError = signUpError
        self.signInError = signInError
        self.signOutError = signOutError
    }

    func restoreSession() async throws -> UserSession? {
        if let restoreError { throw restoreError }
        return restoredSession
    }

    func signUp(email: String, password: String) async throws -> UserSession {
        if let signUpError { throw signUpError }
        return signUpSession
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        if let signInError { throw signInError }
        return signInSession
    }

    func signOut() async throws {
        if let signOutError { throw signOutError }
    }
}

