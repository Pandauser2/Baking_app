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

    func testSignUpEmailConfirmationRequiredShowsMessage() async {
        let client = FakeAuthClient(signUpOutcome: .emailConfirmationRequired)
        let manager = AuthManager(client: client)

        await manager.signUp(email: "new@example.com", password: "password123")

        XCTAssertEqual(manager.status, .signedOut)
        XCTAssertEqual(manager.infoMessage, "Account created. Check your email to confirm your account.")
    }

    func testHandleAuthCallbackRejectsInvalidURL() async {
        let client = FakeAuthClient(authCallbackURL: URL(string: "bakingapp://auth-callback")!)
        let manager = AuthManager(client: client)

        await manager.handleAuthCallback(URL(string: "bakingapp://wrong-host?code=abc")!)

        if case .error(let message) = manager.status {
            XCTAssertEqual(message, "The confirmation link is invalid or expired. Request a new email and try again.")
        } else {
            XCTFail("Expected error status")
        }
        XCTAssertEqual(client.handleCallbackCallCount, 0)
    }

    func testHandleAuthCallbackRefreshesSessionAndSignsIn() async {
        let confirmed = UserSession(userID: UUID(), email: "confirmed@example.com")
        let client = FakeAuthClient(
            authCallbackURL: URL(string: "bakingapp://auth-callback")!,
            restoredSession: confirmed
        )
        let manager = AuthManager(client: client)

        await manager.handleAuthCallback(URL(string: "bakingapp://auth-callback?code=abc")!)

        XCTAssertEqual(manager.status, .signedIn(confirmed))
        XCTAssertEqual(manager.infoMessage, "Email confirmed. You're signed in.")
        XCTAssertEqual(client.handleCallbackCallCount, 1)
        XCTAssertEqual(client.restoreCallCount, 1)
    }

    func testHandleAuthCallbackFailureShowsSafeError() async {
        let client = FakeAuthClient(
            authCallbackURL: URL(string: "bakingapp://auth-callback")!,
            callbackError: AppError.authenticationFailed
        )
        let manager = AuthManager(client: client)

        await manager.handleAuthCallback(URL(string: "bakingapp://auth-callback?code=abc")!)

        if case .error(let message) = manager.status {
            XCTAssertEqual(message, "The confirmation link is invalid or expired. Request a new email and try again.")
        } else {
            XCTFail("Expected error status")
        }
    }
}

private final class FakeAuthClient: AuthClient {
    let authCallbackURL: URL
    var restoredSession: UserSession?
    var signUpOutcome: SignUpOutcome = .signedIn(UserSession(userID: UUID(), email: "new@example.com"))
    var signInSession: UserSession = UserSession(userID: UUID(), email: "in@example.com")
    var restoreError: Error?
    var signUpError: Error?
    var signInError: Error?
    var signOutError: Error?
    var callbackError: Error?
    var callbackSession: UserSession = UserSession(userID: UUID(), email: "cb@example.com")
    private(set) var restoreCallCount = 0
    private(set) var handleCallbackCallCount = 0

    init(
        authCallbackURL: URL = URL(string: "bakingapp://auth-callback")!,
        restoredSession: UserSession? = nil,
        signUpOutcome: SignUpOutcome = .signedIn(UserSession(userID: UUID(), email: "new@example.com")),
        restoreError: Error? = nil,
        signUpError: Error? = nil,
        signInError: Error? = nil,
        signOutError: Error? = nil,
        callbackError: Error? = nil
    ) {
        self.authCallbackURL = authCallbackURL
        self.restoredSession = restoredSession
        self.signUpOutcome = signUpOutcome
        self.restoreError = restoreError
        self.signUpError = signUpError
        self.signInError = signInError
        self.signOutError = signOutError
        self.callbackError = callbackError
    }

    func restoreSession() async throws -> UserSession? {
        restoreCallCount += 1
        if let restoreError { throw restoreError }
        return restoredSession
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        if let signUpError { throw signUpError }
        return signUpOutcome
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        if let signInError { throw signInError }
        return signInSession
    }

    func handleAuthCallback(url: URL) async throws -> UserSession {
        handleCallbackCallCount += 1
        if let callbackError { throw callbackError }
        return callbackSession
    }

    func signOut() async throws {
        if let signOutError { throw signOutError }
    }
}

