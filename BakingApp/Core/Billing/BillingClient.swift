import Foundation

struct BillingCustomerInfo: Equatable {
    let hasEntitlement: Bool
}

protocol BillingClient {
    func configure(apiKey: String)
    func fetchOfferings() async throws -> [SubscriptionOffer]
    func purchase(productID: String) async throws -> BillingCustomerInfo
    func restorePurchases() async throws -> BillingCustomerInfo
    func refreshCustomerInfo() async throws -> BillingCustomerInfo
}

