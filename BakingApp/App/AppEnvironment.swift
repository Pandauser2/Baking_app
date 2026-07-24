import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let configResult: Result<AppConfig, AppConfigError>
    let authManager: AuthManager
    let billingManager: BillingManager
    let onboardingStore: OnboardingStore
    let analytics: AnalyticsTracking

    init(
        configResult: Result<AppConfig, AppConfigError>,
        authManager: AuthManager,
        billingManager: BillingManager,
        onboardingStore: OnboardingStore,
        analytics: AnalyticsTracking
    ) {
        self.configResult = configResult
        self.authManager = authManager
        self.billingManager = billingManager
        self.onboardingStore = onboardingStore
        self.analytics = analytics
    }

    static func live() -> AppEnvironment {
        let configResult: Result<AppConfig, AppConfigError>
        do {
            let config = try AppConfig.load()
            configResult = .success(config)
        } catch let configError as AppConfigError {
            configResult = .failure(configError)
        } catch {
            configResult = .failure(.missingValue("Unexpected configuration error: \(error.localizedDescription)"))
        }
        #if DEBUG
        assertRequiredConfiguration(configResult)
        #endif

        switch configResult {
        case .success(let config):
            FirebaseBootstrapper.configure(hasPlist: config.hasFirebasePlist)
            let analytics: AnalyticsTracking = config.hasFirebasePlist ? FirebaseAnalyticsTracker() : NoopAnalyticsTracker()
            let authManager = AuthManager(
                client: SupabaseAuthClient(
                    supabaseURL: config.supabaseURL,
                    anonKey: config.supabaseAnonKey
                )
            )
            let billingClient = RevenueCatBillingClient(entitlementID: config.revenueCatEntitlementID)
            let billingManager = BillingManager(client: billingClient)
            billingManager.configure(apiKey: config.revenueCatPublicKey)
            return AppEnvironment(
                configResult: configResult,
                authManager: authManager,
                billingManager: billingManager,
                onboardingStore: OnboardingStore(),
                analytics: analytics
            )
        case .failure:
            let fallbackAuth = AuthManager(client: NoopAuthClient())
            let fallbackBilling = BillingManager(client: NoopBillingClient())
            return AppEnvironment(
                configResult: configResult,
                authManager: fallbackAuth,
                billingManager: fallbackBilling,
                onboardingStore: OnboardingStore(),
                analytics: NoopAnalyticsTracker()
            )
        }
    }
}

private struct NoopAuthClient: AuthClient {
    func restoreSession() async throws -> UserSession? { nil }
    func signUp(email: String, password: String) async throws -> UserSession {
        throw AppError.configuration("Configuration missing")
    }
    func signIn(email: String, password: String) async throws -> UserSession {
        throw AppError.configuration("Configuration missing")
    }
    func signOut() async throws {}
}

private struct NoopBillingClient: BillingClient {
    func configure(apiKey: String) {}
    func fetchOfferings() async throws -> [SubscriptionOffer] { throw AppError.configuration("Configuration missing") }
    func purchase(productID: String) async throws -> BillingCustomerInfo { throw AppError.configuration("Configuration missing") }
    func restorePurchases() async throws -> BillingCustomerInfo { throw AppError.configuration("Configuration missing") }
    func refreshCustomerInfo() async throws -> BillingCustomerInfo { BillingCustomerInfo(hasEntitlement: false) }
}

private struct NoopAnalyticsTracker: AnalyticsTracking {
    func track(_ event: AnalyticsEventName) {}
}

