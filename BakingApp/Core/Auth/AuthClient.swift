import Foundation

protocol AuthClient {
    func restoreSession() async throws -> UserSession?
    func signUp(email: String, password: String) async throws -> UserSession
    func signIn(email: String, password: String) async throws -> UserSession
    func signOut() async throws
}

