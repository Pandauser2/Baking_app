import XCTest
@testable import BakingApp

@MainActor
final class BillingManagerTests: XCTestCase {
    func testNoLaunchArgumentEntitlementRemainsRevenueCatControlled() async {
        let client = FakeBillingClient(refreshInfo: BillingCustomerInfo(hasEntitlement: false))
        let manager = BillingManager(client: client, launchArguments: [])

        await manager.refreshEntitlement()
        XCTAssertFalse(manager.hasProEntitlement)

        client.refreshInfo = BillingCustomerInfo(hasEntitlement: true)
        await manager.refreshEntitlement()
        XCTAssertTrue(manager.hasProEntitlement)
    }

    func testExactLaunchArgumentEnablesQAEntitlementOverrideInDebug() async {
        let client = FakeBillingClient(refreshInfo: BillingCustomerInfo(hasEntitlement: false))
        let manager = BillingManager(client: client, launchArguments: ["-qaProEntitlement"])

        XCTAssertTrue(manager.hasProEntitlement)
        await manager.refreshEntitlement()
        XCTAssertTrue(manager.hasProEntitlement)
    }

    func testUnrelatedLaunchArgumentsDoNotEnableOverride() async {
        let client = FakeBillingClient(refreshInfo: BillingCustomerInfo(hasEntitlement: false))
        let manager = BillingManager(client: client, launchArguments: ["-qaProEntitlements", "-qa", "-otherFlag"])

        await manager.refreshEntitlement()
        XCTAssertFalse(manager.hasProEntitlement)
    }

    func testRefreshFailureCannotDisableActiveQAOverride() async {
        let client = FakeBillingClient(
            refreshInfo: BillingCustomerInfo(hasEntitlement: true),
            refreshError: AppError.unknown("refresh failed")
        )
        let manager = BillingManager(client: client, launchArguments: ["-qaProEntitlement"])

        XCTAssertTrue(manager.hasProEntitlement)
        await manager.refreshEntitlement()
        XCTAssertTrue(manager.hasProEntitlement)
    }

    func testProductionPathDoesNotDefaultToProWithoutOverride() async {
        let client = FakeBillingClient(refreshInfo: BillingCustomerInfo(hasEntitlement: false))
        let manager = BillingManager(client: client, launchArguments: [""])

        XCTAssertFalse(manager.hasProEntitlement)
    }

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

private final class FakeBillingClient: BillingClient {
    var offerings: [SubscriptionOffer] = []
    var purchaseInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var restoreInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var refreshInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false)
    var offeringsError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var refreshError: Error?

    init(
        offerings: [SubscriptionOffer] = [],
        purchaseInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false),
        restoreInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false),
        refreshInfo: BillingCustomerInfo = BillingCustomerInfo(hasEntitlement: false),
        offeringsError: Error? = nil,
        purchaseError: Error? = nil,
        restoreError: Error? = nil,
        refreshError: Error? = nil
    ) {
        self.offerings = offerings
        self.purchaseInfo = purchaseInfo
        self.restoreInfo = restoreInfo
        self.refreshInfo = refreshInfo
        self.offeringsError = offeringsError
        self.purchaseError = purchaseError
        self.restoreError = restoreError
        self.refreshError = refreshError
    }

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

