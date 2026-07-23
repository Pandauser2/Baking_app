import Foundation

@MainActor
final class BillingManager: ObservableObject {
    @Published private(set) var state: BillingState = .loading
    @Published private(set) var offers: [SubscriptionOffer] = []
    @Published private(set) var hasProEntitlement: Bool = false
    @Published var bannerMessage: String?

    private let client: BillingClient

    init(client: BillingClient) {
        self.client = client
    }

    func configure(apiKey: String) {
        client.configure(apiKey: apiKey)
    }

    func loadOfferings() async {
        state = .loading
        do {
            offers = try await client.fetchOfferings()
            state = .ready
        } catch let appError as AppError {
            state = .failure(appError.errorDescription ?? "Subscriptions are unavailable")
            bannerMessage = appError.errorDescription
        } catch {
            state = .failure(AppError.offeringsUnavailable.errorDescription ?? "Subscriptions are unavailable")
            bannerMessage = AppError.offeringsUnavailable.errorDescription
        }
    }

    func purchase(productID: String) async {
        state = .loading
        do {
            let info = try await client.purchase(productID: productID)
            hasProEntitlement = info.hasEntitlement
            state = .purchaseSuccess
            bannerMessage = nil
        } catch let appError as AppError {
            if appError == .purchaseCancelled {
                state = .cancelled
            } else {
                state = .failure(appError.errorDescription ?? "Purchase failed")
            }
            bannerMessage = appError.errorDescription
        } catch {
            state = .failure(AppError.purchaseFailed.errorDescription ?? "Purchase failed")
            bannerMessage = AppError.purchaseFailed.errorDescription
        }
    }

    func restorePurchases() async {
        do {
            let info = try await client.restorePurchases()
            hasProEntitlement = info.hasEntitlement
            bannerMessage = "Purchases restored."
        } catch let appError as AppError {
            bannerMessage = appError.errorDescription
        } catch {
            bannerMessage = AppError.restoreFailed.errorDescription
        }
    }

    func refreshEntitlement() async {
        do {
            hasProEntitlement = try await client.refreshCustomerInfo().hasEntitlement
        } catch {
            hasProEntitlement = false
        }
    }
}

