import XCTest
@testable import BakingApp

final class StarterValidationTests: XCTestCase {
    func testStarterNameValidationRejectsEmpty() {
        XCTAssertThrowsError(try StarterValidation.validateStarterName("   "))
    }

    func testStarterHydrationValidationRejectsOutOfRange() {
        XCTAssertThrowsError(try StarterValidation.validateHydration(10))
    }

    func testFeedingValidationRejectsNegativeIngredient() {
        XCTAssertThrowsError(
            try StarterValidation.validateFeedingLog(
                roomTempC: 24,
                flourG: -1,
                waterG: 20,
                starterG: 20
            )
        )
    }

    func testFeedingValidationRejectsImplausibleRoomTemp() {
        XCTAssertThrowsError(
            try StarterValidation.validateFeedingLog(
                roomTempC: 90,
                flourG: 20,
                waterG: 20,
                starterG: 20
            )
        )
    }
}

