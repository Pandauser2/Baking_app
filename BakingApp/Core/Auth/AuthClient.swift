import Foundation

enum SignUpOutcome: Equatable {
    case signedIn(UserSession)
    case emailConfirmationRequired
}

protocol AuthClient {
    var authCallbackURL: URL { get }
    func restoreSession() async throws -> UserSession?
    func signUp(email: String, password: String) async throws -> SignUpOutcome
    func signIn(email: String, password: String) async throws -> UserSession
    func handleAuthCallback(url: URL) async throws -> UserSession
    func signOut() async throws
}

