import Foundation
import RevenueCat

final class RevenueCatBillingClient: BillingClient {
    private let entitlementID: String
    private var packagesByID: [String: Package] = [:]

    init(entitlementID: String) {
        self.entitlementID = entitlementID
    }

    func configure(apiKey: String) {
        Purchases.configure(withAPIKey: apiKey)
    }

    func fetchOfferings() async throws -> [SubscriptionOffer] {
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else {
            throw AppError.offeringsUnavailable
        }

        packagesByID.removeAll()
        let selectedPackages = current.availablePackages.filter {
            $0.packageType == .monthly || $0.packageType == .annual
        }

        if selectedPackages.isEmpty {
            throw AppError.offeringsUnavailable
        }

        var offers: [SubscriptionOffer] = []
        for package in selectedPackages {
            packagesByID[package.storeProduct.productIdentifier] = package
            let title = package.packageType == .annual ? "Yearly" : "Monthly"
            offers.append(
                SubscriptionOffer(
                    id: package.storeProduct.productIdentifier,
                    title: title,
                    price: package.storeProduct.localizedPriceString
                )
            )
        }
        return offers
    }

    func purchase(productID: String) async throws -> BillingCustomerInfo {
        guard let package = packagesByID[productID] else {
            throw AppError.offeringsUnavailable
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            let hasEntitlement = result.customerInfo.entitlements[entitlementID]?.isActive == true
            return BillingCustomerInfo(hasEntitlement: hasEntitlement)
        } catch {
            let nsError = error as NSError
            if nsError.code == ErrorCode.purchaseCancelledError.rawValue {
                throw AppError.purchaseCancelled
            }
            throw AppError.purchaseFailed
        }
    }

    func restorePurchases() async throws -> BillingCustomerInfo {
        do {
            let info = try await Purchases.shared.restorePurchases()
            let hasEntitlement = info.entitlements[entitlementID]?.isActive == true
            return BillingCustomerInfo(hasEntitlement: hasEntitlement)
        } catch {
            throw AppError.restoreFailed
        }
    }

    func refreshCustomerInfo() async throws -> BillingCustomerInfo {
        let info = try await Purchases.shared.customerInfo()
        let hasEntitlement = info.entitlements[entitlementID]?.isActive == true
        return BillingCustomerInfo(hasEntitlement: hasEntitlement)
    }
}

