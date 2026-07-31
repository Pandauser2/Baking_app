import XCTest

private enum UITestIDs {
    static let uiTestingArgument = "-uiTesting"
    static let populatedTimelineArgument = "-uiTestingTimelinePopulated"
    static let openStarterDetails = "home.openStarterDetails"
    static let workflowTimeline = "starter.workflow.timeline"
    static let workflowFeedingHistory = "starter.workflow.feedingHistory"
    static let workflowLogFeeding = "starter.workflow.logFeeding"
    static let workflowScanStarter = "starter.workflow.scanStarter"
    static let homeRoot = "home.root"
    static let starterDetailRoot = "starter.detail.root"
    static let timelineRoot = "starter.timeline.root"
    static let feedingHistoryRoot = "starter.feedingHistory.root"
    static let feedingLogRoot = "starter.feedingLog.root"
    static let scanRoot = "starter.scan.root"
}

final class HomeNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            UITestIDs.uiTestingArgument,
            "-qaProEntitlement",
        ]
    }

    func testHomeDetailsTimelineBackToHome() {
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        tapBack()
        assertStarterDetails()
        tapBack()
        assertHome()
    }

    func testRepeatedEntryExitAndDoubleTapBack() {
        app.launch()
        for _ in 0..<2 {
            openStarterDetails()
            openTimeline()
            tapBack()
            assertStarterDetails()
            tapBack()
            assertHome()
        }

        openStarterDetails()
        openTimeline()
        // Rapid double tap must not blank the stack.
        tapBack()
        tapBack()
        assertHome()
    }

    func testRestartThenSameFlow() {
        app.launch()
        openStarterDetails()
        openTimeline()
        tapBack()
        assertStarterDetails()

        app.terminate()
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        tapBack()
        assertStarterDetails()
        tapBack()
        assertHome()
    }

    func testTimelineEmptyAndPopulated() {
        app.launchArguments = [UITestIDs.uiTestingArgument, "-qaProEntitlement"]
        app.launch()
        openStarterDetails()
        openTimeline()
        XCTAssertTrue(app.staticTexts["No starter scans yet."].waitForExistence(timeout: 5))
        tapBack()
        assertStarterDetails()
        app.terminate()

        app.launchArguments = [
            UITestIDs.uiTestingArgument,
            UITestIDs.populatedTimelineArgument,
            "-qaProEntitlement",
        ]
        app.launch()
        openStarterDetails()
        openTimeline()
        XCTAssertTrue(
            app.staticTexts["UITest saved analysis remains intact."].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Outcome: Followed"].exists)
        tapBack()
        assertStarterDetails()
    }

    func testSwipeBackFromTimeline() {
        app.launch()
        openStarterDetails()
        openTimeline()
        swipeBackFromLeftEdge()
        assertStarterDetails()
    }

    func testWorkflowScreensBackNavigation() {
        app.launch()
        openStarterDetails()

        app.descendants(matching: .any)[UITestIDs.workflowFeedingHistory].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.feedingHistoryRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
        tapBack()
        assertStarterDetails()

        app.descendants(matching: .any)[UITestIDs.workflowLogFeeding].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.feedingLogRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
        tapBack()
        assertStarterDetails()

        app.descendants(matching: .any)[UITestIDs.workflowScanStarter].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.scanRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
        tapBack()
        assertStarterDetails()
    }

    func testDebugSchemeLaunchWithoutQAFlag() {
        app.launchArguments = [UITestIDs.uiTestingArgument]
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        tapBack()
        assertStarterDetails()
    }

    private func assertHome() {
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.homeRoot]
                .firstMatch.waitForExistence(timeout: 8)
        )
    }

    private func assertStarterDetails() {
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.starterDetailRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    private func openStarterDetails() {
        let button = app.descendants(matching: .any)[UITestIDs.openStarterDetails].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
        assertStarterDetails()
    }

    private func openTimeline() {
        let link = app.descendants(matching: .any)[UITestIDs.workflowTimeline].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.timelineRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    private func tapBack() {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 3))
        let backButton = navBar.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Native back control missing")
        XCTAssertFalse(backButton.label.isEmpty, "Back control must be VoiceOver-labelled")
        backButton.tap()
    }

    private func swipeBackFromLeftEdge() {
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        coordinate.press(forDuration: 0.05, thenDragTo: end)
    }
}
