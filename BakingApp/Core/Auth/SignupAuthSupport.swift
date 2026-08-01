import Foundation

enum SignupPasswordRules {
    static let minimumLength = 8
    static let tooShortMessage = "Password must be at least 8 characters."

    /// Returns a user-facing error when the password is invalid for signup; otherwise `nil`.
    static func validationErrorMessage(for password: String) -> String? {
        guard password.count >= minimumLength else {
            return tooShortMessage
        }
        return nil
    }
}

enum SignupErrorMapper {
    static let genericFailureMessage = "We could not create your account. Please try again."

    static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .authenticationFailed:
                return genericFailureMessage
            case .unknown(let message):
                return sanitizedServerMessage(message) ?? genericFailureMessage
            default:
                return appError.errorDescription ?? genericFailureMessage
            }
        }

        return sanitizedServerMessage(error.localizedDescription) ?? genericFailureMessage
    }

    /// Keeps useful, non-sensitive server text; drops anything that looks like raw diagnostics.
    private static func sanitizedServerMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.contains("http://") || lower.contains("https://") { return nil }
        if lower.contains("token") || lower.contains("bearer") { return nil }
        if lower.contains("apikey") || lower.contains("api_key") { return nil }
        if trimmed.count > 180 { return nil }

        if lower.contains("weak") && lower.contains("password") {
            return SignupPasswordRules.tooShortMessage
        }
        if lower.contains("password") && (lower.contains("at least") || lower.contains("too short") || lower.contains("least 6") || lower.contains("least 8")) {
            return SignupPasswordRules.tooShortMessage
        }
        if lower.contains("invalid") && lower.contains("email") {
            return "Please enter a valid email address."
        }
        if lower.contains("signup") && lower.contains("disabled") {
            return "Account creation is temporarily unavailable. Please try again later."
        }
        if lower.contains("rate") && lower.contains("limit") {
            return "Too many attempts. Please wait a moment and try again."
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("timed out") || lower.contains("timeout") {
            return "Network error. Check your connection and try again."
        }

        // Preserve other concise server messages that passed the safety filters.
        return trimmed
    }
}
