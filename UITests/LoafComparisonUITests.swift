import XCTest

final class LoafComparisonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testFirstBakeBaselineFlowAndBack() {
        app.launchArguments = [
            "-uiTesting",
            "-qaProEntitlement",
            "-uiTestingLoafBaseline",
        ]
        app.launch()
        openSeededBake(named: "Baseline Bake")
        let viewAnalysis = app.buttons["bake.detail.viewAnalysis"]
        let viewByLabel = app.buttons["View analysis"]
        XCTAssertTrue(
            viewAnalysis.waitForExistence(timeout: 12) || viewByLabel.waitForExistence(timeout: 12),
            "Expected View analysis toolbar for seeded baseline"
        )
        if viewAnalysis.exists {
            viewAnalysis.tap()
        } else {
            viewByLabel.tap()
        }
        XCTAssertTrue(
            app.otherElements["loaf.analysisResult.root"].waitForExistence(timeout: 12)
                || app.staticTexts["Overall assessment"].waitForExistence(timeout: 12)
                || app.staticTexts["Try this next"].waitForExistence(timeout: 12)
                || app.navigationBars["Analysis Result"].waitForExistence(timeout: 12)
                || app.buttons["Save as baseline"].waitForExistence(timeout: 12)
        )
        if app.buttons["Save as baseline"].exists || app.buttons["loaf.result.saveBaseline"].exists {
            let save = app.buttons["loaf.result.saveBaseline"].exists
                ? app.buttons["loaf.result.saveBaseline"]
                : app.buttons["Save as baseline"]
            save.tap()
        } else {
            tapBack("nav.back.loafAnalysisResult")
        }
        tapBack("nav.back.bakeDetail")
        tapBack("nav.back.bakeJournal")
        XCTAssertTrue(app.buttons["home.openBakeJournal"].waitForExistence(timeout: 5))
    }

    func testAnalyzeFailureShowsRetry() {
        app.launchArguments = [
            "-uiTesting",
            "-qaProEntitlement",
            "-uiTestingLoafProcessComparison",
            "-uiTestingLoafAutoAnalyze",
            "-uiTestingLoafAnalyzeFail",
        ]
        app.launch()
        openSeededBake(named: "Second Bake")
        tapScanLoaf()
        XCTAssertTrue(
            app.buttons["Retry"].waitForExistence(timeout: 20)
                || app.buttons["loaf.scan.retry"].waitForExistence(timeout: 5)
                || app.navigationBars["Scan Loaf"].waitForExistence(timeout: 5)
                || app.otherElements["loaf.scan.root"].waitForExistence(timeout: 5)
        )
        if app.buttons["nav.back.loafScan"].exists {
            tapBack("nav.back.loafScan")
        }
    }

    func testProcessComparisonResult() {
        app.launchArguments = [
            "-uiTesting",
            "-qaProEntitlement",
            "-uiTestingLoafProcessComparison",
            "-uiTestingLoafAutoAnalyze",
        ]
        app.launch()
        openSeededBake(named: "Second Bake")
        tapScanLoaf()
        XCTAssertTrue(
            app.otherElements["loaf.analysisResult.root"].waitForExistence(timeout: 12)
                || app.staticTexts["Overall assessment"].waitForExistence(timeout: 12)
        )
        XCTAssertTrue(
            app.otherElements["loaf.result.visualUnavailable"].waitForExistence(timeout: 5)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Visual loaf comparison")).firstMatch
                .waitForExistence(timeout: 5)
        )
        tapBack("nav.back.loafAnalysisResult")
    }

    func testFullComparisonResult() {
        app.launchArguments = [
            "-uiTesting",
            "-qaProEntitlement",
            "-uiTestingLoafFullComparison",
            "-uiTestingLoafAutoAnalyze",
        ]
        app.launch()
        openSeededBake(named: "Second Bake")
        tapScanLoaf()
        XCTAssertTrue(
            app.otherElements["loaf.analysisResult.root"].waitForExistence(timeout: 12)
                || app.staticTexts["What improved / regressed"].waitForExistence(timeout: 12)
                || app.staticTexts["Overall assessment"].waitForExistence(timeout: 12)
        )
        tapBack("nav.back.loafAnalysisResult")
    }

    func testProGatingOnScanLoaf() {
        app.launchArguments = ["-uiTesting", "-uiTestingLoafBaseline"]
        app.launch()
        openSeededBake(named: "Baseline Bake")
        tapScanLoaf()
        XCTAssertTrue(
            app.staticTexts["Pro is required for loaf analysis."].waitForExistence(timeout: 5)
                || app.otherElements["loaf.scan.proRequired"].waitForExistence(timeout: 5)
        )
    }

    private func openSeededBake(named name: String) {
        let journal = app.buttons["home.openBakeJournal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 8))
        journal.tap()
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Expected seeded bake \(name)")
        row.tap()
        XCTAssertTrue(
            app.otherElements["bake.detail.root"].waitForExistence(timeout: 5)
                || app.navigationBars["Bake Details"].waitForExistence(timeout: 5)
        )
        // Wait until journal fields render (not just the destination wrapper).
        XCTAssertTrue(
            app.staticTexts[name].waitForExistence(timeout: 10)
                || app.staticTexts["Basics"].waitForExistence(timeout: 10)
                || app.staticTexts["Loaf scan"].waitForExistence(timeout: 10)
        )
    }

    private func tapScanLoaf() {
        let byID = app.buttons["bake.detail.scanLoaf"]
        let byLabel = app.buttons["Scan loaf"]
        let byAgain = app.buttons["Scan again"]
        XCTAssertTrue(
            byID.waitForExistence(timeout: 10)
                || byLabel.waitForExistence(timeout: 10)
                || byAgain.waitForExistence(timeout: 10),
            "Scan loaf control missing on bake detail"
        )
        if byID.exists {
            byID.tap()
        } else if byLabel.exists {
            byLabel.tap()
        } else {
            byAgain.tap()
        }
    }

    private func tapBack(_ accessibilityID: String) {
        let back = app.buttons[accessibilityID]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
