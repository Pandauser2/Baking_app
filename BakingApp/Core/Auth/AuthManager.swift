import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var status: AuthStatus = .loadingSession

    private let client: AuthClient

    init(client: AuthClient) {
        self.client = client
    }

    func restoreSession() async {
        status = .loadingSession
        do {
            if let session = try await client.restoreSession() {
                status = .signedIn(session)
            } else {
                status = .signedOut
            }
        } catch {
            status = .error(message: AppError.sessionRestoreFailed.errorDescription ?? "Session restore failed")
        }
    }

    func signUp(email: String, password: String) async {
        do {
            let session = try await client.signUp(email: email, password: password)
            status = .signedIn(session)
        } catch {
            status = .error(message: AppError.authenticationFailed.errorDescription ?? "Authentication failed")
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await client.signIn(email: email, password: password)
            status = .signedIn(session)
        } catch {
            status = .error(message: AppError.authenticationFailed.errorDescription ?? "Authentication failed")
        }
    }

    func signOut() async {
        do {
            try await client.signOut()
        } catch {
            // Keep a deterministic local sign-out state for reliability.
        }
        status = .signedOut
    }

    func clearErrorToSignedOut() {
        if case .error = status {
            status = .signedOut
        }
    }
}

