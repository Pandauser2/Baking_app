import XCTest
@testable import BakingApp

@MainActor
final class OnboardingStoreTests: XCTestCase {
    func testOnboardingCompletionPersists() {
        let suiteName = "OnboardingStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.isCompleted)

        store.complete()
        XCTAssertTrue(store.isCompleted)

        let reloaded = OnboardingStore(defaults: defaults)
        XCTAssertTrue(reloaded.isCompleted)
    }
}

