import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let configResult: Result<AppConfig, AppConfigError>
    let authManager: AuthManager
    let billingManager: BillingManager
    let onboardingStore: OnboardingStore
    let analytics: AnalyticsTracking
    let loafAnalysisRepository: LoafAnalysisRepository
    let starterRepository: StarterRepository

    init(
        configResult: Result<AppConfig, AppConfigError>,
        authManager: AuthManager,
        billingManager: BillingManager,
        onboardingStore: OnboardingStore,
        analytics: AnalyticsTracking,
        loafAnalysisRepository: LoafAnalysisRepository,
        starterRepository: StarterRepository
    ) {
        self.configResult = configResult
        self.authManager = authManager
        self.billingManager = billingManager
        self.onboardingStore = onboardingStore
        self.analytics = analytics
        self.loafAnalysisRepository = loafAnalysisRepository
        self.starterRepository = starterRepository
    }

    static func live() -> AppEnvironment {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let fallbackAuth = AuthManager(client: NoopAuthClient())
            let fallbackBilling = BillingManager(client: NoopBillingClient())
            return AppEnvironment(
                configResult: .failure(.missingValue("Skipping live services during tests")),
                authManager: fallbackAuth,
                billingManager: fallbackBilling,
                onboardingStore: OnboardingStore(),
                analytics: NoopAnalyticsTracker(),
                loafAnalysisRepository: NoopLoafAnalysisRepository(),
                starterRepository: NoopStarterRepository()
            )
        }

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
            let loafAnalysisRepository = SupabaseLoafAnalysisRepository(
                supabaseURL: config.supabaseURL,
                anonKey: config.supabaseAnonKey
            )
            let starterRepository = SupabaseStarterRepository(
                supabaseURL: config.supabaseURL,
                anonKey: config.supabaseAnonKey
            )
            return AppEnvironment(
                configResult: configResult,
                authManager: authManager,
                billingManager: billingManager,
                onboardingStore: OnboardingStore(),
                analytics: analytics,
                loafAnalysisRepository: loafAnalysisRepository,
                starterRepository: starterRepository
            )
        case .failure:
            let fallbackAuth = AuthManager(client: NoopAuthClient())
            let fallbackBilling = BillingManager(client: NoopBillingClient())
            return AppEnvironment(
                configResult: configResult,
                authManager: fallbackAuth,
                billingManager: fallbackBilling,
                onboardingStore: OnboardingStore(),
                analytics: NoopAnalyticsTracker(),
                loafAnalysisRepository: NoopLoafAnalysisRepository(),
                starterRepository: NoopStarterRepository()
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

private struct NoopLoafAnalysisRepository: LoafAnalysisRepository {
    func uploadImage(_ data: Data, userID: UUID) async throws -> String { throw AppError.configuration("Configuration missing") }
    func analyzeLoaf(imagePath: String, promptVersion: String) async throws -> LoafScan { throw AppError.configuration("Configuration missing") }
    func fetchHistory() async throws -> [LoafScan] { [] }
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL { throw AppError.configuration("Configuration missing") }
}

private struct NoopStarterRepository: StarterRepository {
    func listStarters() async throws -> [Starter] { [] }
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter {
        throw AppError.configuration("Configuration missing")
    }
    func setActiveStarter(starterID: UUID) async throws {}
    func fetchStarter(starterID: UUID) async throws -> Starter {
        throw AppError.configuration("Configuration missing")
    }
    func fetchStarterState(starterID: UUID) async throws -> StarterState? { nil }
    func createFeedingLog(starterID: UUID, loggedAt: Date, roomTempC: Double, flourG: Int?, waterG: Int?, starterG: Int?, notes: String?) async throws -> FeedingLog {
        throw AppError.configuration("Configuration missing")
    }
    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] { [] }
    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String {
        throw AppError.configuration("Configuration missing")
    }
    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAnalyzeResult {
        throw AppError.configuration("Configuration missing")
    }
    func persistStarterAnalysis(starterID: UUID, imagePath: String, qualityScore: Double?, qualityIssue: String?, model: String, promptVersion: String, response: StarterAIResponse) async throws -> PersistedStarterAnalysisIDs {
        throw AppError.configuration("Configuration missing")
    }
    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] { [] }
    func updateRecommendationOutcome(recommendationID: UUID, outcome: RecommendationOutcome) async throws -> Recommendation {
        throw AppError.configuration("Configuration missing")
    }
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        throw AppError.configuration("Configuration missing")
    }
}

