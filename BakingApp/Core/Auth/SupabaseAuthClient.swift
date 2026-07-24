import Foundation
import Supabase

final class SupabaseAuthClient: AuthClient {
    private let client: SupabaseClient

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

    func signUp(email: String, password: String) async throws -> UserSession {
        let response = try await client.auth.signUp(email: email, password: password)
        let user = response.user
        return UserSession(userID: user.id, email: user.email)
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        let session = try await client.auth.signIn(email: email, password: password)
        return UserSession(userID: session.user.id, email: session.user.email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}

