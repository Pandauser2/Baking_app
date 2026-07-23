import XCTest
@testable import BakingApp

@MainActor
final class BillingManagerTests: XCTestCase {
    func testEntitlementRefreshMapsToProState() async {
        let client = FakeBillingClient(refreshInfo: BillingCustomerInfo(hasEntitlement: true))
        let manager = BillingManager(client: client)

        await manager.refreshEntitlement()

        XCTAssertTrue(manager.hasProEntitlement)
    }

    func testPurchaseCancelledSetsCancelledState() async {
        let offer = SubscriptionOffer(id: "monthly", title: "Monthly", price: "$4.99")
        let client = FakeBillingClient(
            offerings: [offer],
            purchaseError: AppError.purchaseCancelled
        )
        let manager = BillingManager(client: client)
        await manager.loadOfferings()

        await manager.purchase(productID: offer.id)

        XCTAssertEqual(manager.state, .cancelled)
    }

    func testPurchaseFailureSetsFailureState() async {
        let offer = SubscriptionOffer(id: "yearly", title: "Yearly", price: "$39.99")
        let client = FakeBillingClient(
            offerings: [offer],
            purchaseError: AppError.purchaseFailed
        )
        let manager = BillingManager(client: client)
        await manager.loadOfferings()

        await manager.purchase(productID: offer.id)

        if case .failure = manager.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected failure state")
        }
    }
}

private struct FakeBillingClient: BillingClient {
    var offerings: [SubscriptionOffer] = []
    var purchaseInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var restoreInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var refreshInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var offeringsError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var refreshError: Error?

    func configure(apiKey: String) {}

    func fetchOfferings() async throws -> [SubscriptionOffer] {
        if let offeringsError { throw offeringsError }
        return offerings
    }

    func purchase(productID: String) async throws -> BillingCustomerInfo {
        if let purchaseError { throw purchaseError }
        return purchaseInfo
    }

    func restorePurchases() async throws -> BillingCustomerInfo {
        if let restoreError { throw restoreError }
        return restoreInfo
    }

    func refreshCustomerInfo() async throws -> BillingCustomerInfo {
        if let refreshError { throw refreshError }
        return refreshInfo
    }
}

