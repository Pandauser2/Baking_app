import Foundation
import FirebaseAnalytics

enum AnalyticsEventName: String {
    case signupCompleted = "signup_completed"
    case loginCompleted = "login_completed"
    case onboardingCompleted = "onboarding_completed"
    case paywallViewed = "paywall_viewed"
    case purchaseCompleted = "purchase_completed"
    case purchaseRestored = "purchase_restored"
}

protocol AnalyticsTracking {
    func track(_ event: AnalyticsEventName)
}

struct FirebaseAnalyticsTracker: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {
        Analytics.logEvent(event.rawValue, parameters: nil)
    }
}

