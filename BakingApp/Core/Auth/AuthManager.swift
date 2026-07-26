import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var status: AuthStatus = .loadingSession
    @Published private(set) var infoMessage: String?

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
            let outcome = try await client.signUp(email: email, password: password)
            switch outcome {
            case .signedIn(let session):
                status = .signedIn(session)
                infoMessage = nil
            case .emailConfirmationRequired:
                status = .signedOut
                infoMessage = "Account created. Check your email to confirm your account."
            }
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

    func dismissInfoMessage() {
        infoMessage = nil
    }

    func handleAuthCallback(_ url: URL) async {
        guard acceptsAuthCallback(url) else {
            status = .error(message: "The confirmation link is invalid or expired. Request a new email and try again.")
            return
        }

        do {
            _ = try await client.handleAuthCallback(url: url)
            if let refreshedSession = try await client.restoreSession() {
                status = .signedIn(refreshedSession)
                infoMessage = "Email confirmed. You're signed in."
            } else {
                status = .error(message: "We couldn't finish email confirmation. Please sign in again.")
            }
        } catch {
            status = .error(message: "The confirmation link is invalid or expired. Request a new email and try again.")
        }
    }

    private func acceptsAuthCallback(_ url: URL) -> Bool {
        guard
            let incomingScheme = url.scheme?.lowercased(),
            let incomingHost = url.host?.lowercased(),
            let expectedScheme = client.authCallbackURL.scheme?.lowercased(),
            let expectedHost = client.authCallbackURL.host?.lowercased()
        else {
            return false
        }
        return incomingScheme == expectedScheme && incomingHost == expectedHost
    }
}

