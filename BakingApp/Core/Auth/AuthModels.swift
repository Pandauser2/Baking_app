import Foundation

struct UserSession: Equatable {
    let userID: UUID
    let email: String?
}

enum AuthStatus: Equatable {
    case loadingSession
    case signedOut
    case signedIn(UserSession)
    case error(message: String)
}

enum AppError: LocalizedError, Equatable {
    case configuration(String)
    case authenticationFailed
    case sessionRestoreFailed
    case purchaseFailed
    case purchaseCancelled
    case restoreFailed
    case offeringsUnavailable
    case subscriptionRequired
    case imageValidationFailed(String)
    case uploadFailed
    case analysisFailed
    case malformedResponse
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .configuration:
            return "The app is not configured correctly. Please contact support."
        case .authenticationFailed:
            return "We could not sign you in. Please verify your credentials and try again."
        case .sessionRestoreFailed:
            return "We could not restore your session. Please sign in again."
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        case .purchaseCancelled:
            return "Purchase was cancelled."
        case .restoreFailed:
            return "We could not restore purchases. Please try again."
        case .offeringsUnavailable:
            return "Subscriptions are currently unavailable. Please try again later."
        case .subscriptionRequired:
            return "This feature requires an active Pro subscription."
        case .imageValidationFailed(let message):
            return message
        case .uploadFailed:
            return "Image upload failed. Please try again."
        case .analysisFailed:
            return "Analysis failed. Please try again."
        case .malformedResponse:
            return "We received an invalid analysis response. Please retry."
        case .unknown(let message):
            return message
        }
    }
}

