import XCTest

final class BakeJournalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-qaProEntitlement"]
    }

    func testEmptyJournal() {
        app.launch()
        openBakeJournal()
        XCTAssertTrue(app.otherElements["bake.journal.empty"].waitForExistence(timeout: 5)
            || app.staticTexts["No bakes yet"].waitForExistence(timeout: 5))
        tapBack("nav.back.bakeJournal")
        XCTAssertTrue(app.otherElements["home.root"].waitForExistence(timeout: 5)
            || app.buttons["home.openBakeJournal"].waitForExistence(timeout: 5))
    }

    func testCreateBakeOpenDetailsAndBack() {
        app.launch()
        openBakeJournal()
        let add = app.buttons["bake.journal.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let nameField = app.textFields["bake.create.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UITest Country Loaf")

        // Dismiss keyboard so toolbar Save remains hittable.
        if app.keyboards.element.exists {
            app.keyboards.buttons["return"].tap()
        }
        app.tap()

        let save = app.buttons["bake.create.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save bake control missing")
        save.tap()

        XCTAssertTrue(
            app.otherElements["bake.detail.root"].waitForExistence(timeout: 8)
                || app.navigationBars["Bake Details"].waitForExistence(timeout: 8)
                || app.staticTexts["UITest Country Loaf"].waitForExistence(timeout: 8)
        )

        tapBack("nav.back.bakeDetail")
        XCTAssertTrue(
            app.otherElements["bake.journal.root"].waitForExistence(timeout: 5)
                || app.navigationBars["Bake Journal"].waitForExistence(timeout: 5)
                || app.buttons["bake.journal.add"].waitForExistence(timeout: 5)
        )
        tapBack("nav.back.bakeJournal")
        XCTAssertTrue(app.buttons["home.openBakeJournal"].waitForExistence(timeout: 5))
    }

    private func openBakeJournal() {
        let button = app.buttons["home.openBakeJournal"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
        XCTAssertTrue(app.otherElements["bake.journal.root"].waitForExistence(timeout: 5)
            || app.navigationBars["Bake Journal"].waitForExistence(timeout: 5))
    }

    private func tapBack(_ accessibilityID: String) {
        let back = app.buttons[accessibilityID]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
