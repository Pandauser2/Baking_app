import XCTest
@testable import BakingApp

final class BakeValidationTests: XCTestCase {
    func testValidInputPasses() throws {
        let validated = try BakeValidation.validate(Self.validInput())
        XCTAssertEqual(validated.name, "Country loaf")
        XCTAssertEqual(validated.fermentationTemperatureSource, .room)
    }

    func testBlankNameFails() {
        var input = Self.validInput()
        input.name = "  "
        XCTAssertThrowsError(try BakeValidation.validate(input)) { error in
            XCTAssertEqual(error as? BakeValidationError, .blankName)
        }
    }

    func testRatingOutOfRangeFails() {
        var input = Self.validInput()
        input.resultRating = 6
        XCTAssertThrowsError(try BakeValidation.validate(input)) { error in
            XCTAssertEqual(error as? BakeValidationError, .ratingOutOfRange)
        }
    }

    func testFermentationTempRequiresSource() {
        var input = Self.validInput()
        input.fermentationTemperatureCelsius = 24
        input.fermentationTemperatureSource = nil
        XCTAssertThrowsError(try BakeValidation.validate(input)) { error in
            XCTAssertEqual(error as? BakeValidationError, .fermentationSourceRequired)
        }
    }

    func testEmptyOptionalFermentationClearsBoth() throws {
        var input = Self.validInput()
        input.fermentationTemperatureCelsius = nil
        input.fermentationTemperatureSource = nil
        let validated = try BakeValidation.validate(input)
        XCTAssertNil(validated.fermentationTemperatureCelsius)
        XCTAssertNil(validated.fermentationTemperatureSource)
    }

    private static func validInput() -> BakeCreateInput {
        BakeCreateInput(
            starterID: UUID(),
            bakedAt: Date(),
            name: "Country loaf",
            doughHydrationPercent: 75,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            mixingMethod: BakeMixingMethod.hand.rawValue,
            shapingMethod: BakeShapingMethod.boule.rawValue,
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40,
            resultRating: 4,
            fermentationTemperatureCelsius: 24,
            fermentationTemperatureSource: .room,
            retardationMinutes: 480,
            numberOfFolds: 4,
            steamingMethod: "Tray",
            flourNotes: "Bread flour",
            notes: "Good spring"
        )
    }
}
