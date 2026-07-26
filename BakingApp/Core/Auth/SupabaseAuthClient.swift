import Foundation
import Supabase

final class SupabaseAuthClient: AuthClient {
    private let client: SupabaseClient
    static let callbackURL = URL(string: "bakingapp://auth-callback")!

    var authCallbackURL: URL { Self.callbackURL }

    init(supabaseURL: URL, anonKey: String) {
        self.client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)
    }

    func restoreSession() async throws -> UserSession? {
        do {
            let session = try await client.auth.session
            return UserSession(userID: session.user.id, email: session.user.email)
        } catch {
            return nil
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: Self.callbackURL
        )
        if let session = response.session {
            return .signedIn(UserSession(userID: session.user.id, email: session.user.email))
        }
        return .emailConfirmationRequired
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        let session = try await client.auth.signIn(email: email, password: password)
        return UserSession(userID: session.user.id, email: session.user.email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func handleAuthCallback(url: URL) async throws -> UserSession {
        let session = try await client.auth.session(from: url)
        return UserSession(userID: session.user.id, email: session.user.email)
    }
}

