import Foundation

enum AppConfigError: Error {
    case missingValue(String)
    case invalidURL(String)
}

struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let revenueCatPublicKey: String
    let revenueCatEntitlementID: String
    let hasFirebasePlist: Bool

    static func load(bundle: Bundle = .main) throws -> AppConfig {
        let urlString = try requiredValue("SUPABASE_URL", bundle: bundle)
        guard
            let supabaseURL = URL(string: urlString),
            let scheme = supabaseURL.scheme?.lowercased(),
            (scheme == "https" || scheme == "http"),
            let host = supabaseURL.host,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AppConfigError.invalidURL("SUPABASE_URL is not a valid URL")
        }

        let supabaseAnonKey = try requiredValue("SUPABASE_ANON_KEY", bundle: bundle)
        let revenueCatPublicKey = try requiredValue("REVENUECAT_PUBLIC_KEY", bundle: bundle)
        let entitlementID = try requiredValue("REVENUECAT_ENTITLEMENT_ID", bundle: bundle)

        let hasFirebasePlist = bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil

        return AppConfig(
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            revenueCatPublicKey: revenueCatPublicKey,
            revenueCatEntitlementID: entitlementID,
            hasFirebasePlist: hasFirebasePlist
        )
    }

    private static func requiredValue(_ key: String, bundle: Bundle) throws -> String {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else {
            throw AppConfigError.missingValue("\(key) is missing from Info.plist")
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "$(inherited)" || trimmed.hasPrefix("$(") || trimmed.contains("YOUR_") {
            throw AppConfigError.missingValue("\(key) is not configured")
        }
        return trimmed
    }
}

#if DEBUG
func assertRequiredConfiguration(_ result: Result<AppConfig, AppConfigError>) {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return
    }

    if case .failure(let error) = result {
        switch error {
        case .missingValue(let message), .invalidURL(let message):
            fatalError("Missing app configuration: \(message)")
        }
    }
}
#endif

