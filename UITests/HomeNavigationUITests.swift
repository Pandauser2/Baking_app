import XCTest

private enum UITestIDs {
    static let uiTestingArgument = "-uiTesting"
    static let populatedTimelineArgument = "-uiTestingTimelinePopulated"
    static let seedAnalysisResultArgument = "-uiTestingSeedAnalysisResult"
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
    static let analysisResultRoot = "starter.analysisResult.root"
    static let starterListRoot = "starter.list.root"

    static let backStarterDetail = "nav.back.starterDetail"
    static let backTimeline = "nav.back.timeline"
    static let backFeedingHistory = "nav.back.feedingHistory"
    static let backFeedingLog = "nav.back.feedingLog"
    static let backScan = "nav.back.scan"
    static let backAnalysisResult = "nav.back.analysisResult"
    static let backStarterList = "nav.back.starterList"
}

final class HomeNavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let artifactsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("artifacts/e2e/bug003", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            UITestIDs.uiTestingArgument,
            "-qaProEntitlement",
        ]
        try FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)
    }

    func testHomeDetailsTimelineBackToHome() {
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        screenshot("run_basic_before_timeline_back")
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
        assertStarterDetails()
        screenshot("run_basic_after_timeline_back")
        tapExplicitBack(UITestIDs.backStarterDetail, alsoTapVisibleCoordinates: true)
        assertHome()
    }

    func testRepeatedNavigationTenTimes() {
        app.launch()
        for i in 1...10 {
            openStarterDetails()
            openTimeline()
            tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: i == 1)
            assertStarterDetails()
            tapExplicitBack(UITestIDs.backStarterDetail, alsoTapVisibleCoordinates: false)
            assertHome()
        }
    }

    func testRapidDoubleTapBack() {
        app.launch()
        openStarterDetails()
        openTimeline()
        let back = app.buttons[UITestIDs.backTimeline]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Second tap may land on details back or already home.
        if app.buttons[UITestIDs.backStarterDetail].waitForExistence(timeout: 2) {
            app.buttons[UITestIDs.backStarterDetail]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .tap()
        }
        assertHome()
    }

    func testRestartThenSameFlow() {
        app.launch()
        openStarterDetails()
        openTimeline()
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
        assertStarterDetails()

        app.terminate()
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
        assertStarterDetails()
        tapExplicitBack(UITestIDs.backStarterDetail, alsoTapVisibleCoordinates: true)
        assertHome()
    }

    func testTimelineEmptyAndPopulatedPreservesOutcome() {
        app.launchArguments = [UITestIDs.uiTestingArgument, "-qaProEntitlement"]
        app.launch()
        openStarterDetails()
        openTimeline()
        XCTAssertTrue(app.staticTexts["No starter scans yet."].waitForExistence(timeout: 5))
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
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
        screenshot("populated_timeline_before_back")
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
        assertStarterDetails()
        openTimeline()
        XCTAssertTrue(app.staticTexts["Outcome: Followed"].waitForExistence(timeout: 5))
        screenshot("populated_timeline_after_roundtrip")
    }

    func testSwipeBackFromTimeline() {
        app.launch()
        openStarterDetails()
        openTimeline()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.02)
        assertStarterDetails()
    }

    func testAllWorkflowBackPathsIncludingAnalysisResultAndList() {
        app.launch()
        openStarterDetails()

        app.buttons[UITestIDs.workflowFeedingHistory].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestIDs.feedingHistoryRoot].firstMatch.waitForExistence(timeout: 5))
        tapExplicitBack(UITestIDs.backFeedingHistory, alsoTapVisibleCoordinates: true)
        assertStarterDetails()

        app.buttons[UITestIDs.workflowLogFeeding].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestIDs.feedingLogRoot].firstMatch.waitForExistence(timeout: 5))
        tapExplicitBack(UITestIDs.backFeedingLog, alsoTapVisibleCoordinates: true)
        assertStarterDetails()

        app.buttons[UITestIDs.workflowScanStarter].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestIDs.scanRoot].firstMatch.waitForExistence(timeout: 5))
        tapExplicitBack(UITestIDs.backScan, alsoTapVisibleCoordinates: true)
        assertStarterDetails()

        tapExplicitBack(UITestIDs.backStarterDetail, alsoTapVisibleCoordinates: true)
        assertHome()

        app.buttons["View all starters"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestIDs.starterListRoot].firstMatch.waitForExistence(timeout: 5))
        tapExplicitBack(UITestIDs.backStarterList, alsoTapVisibleCoordinates: true)
        assertHome()

        // Analysis Result → Scan Starter
        app.terminate()
        app.launchArguments = [
            UITestIDs.uiTestingArgument,
            UITestIDs.seedAnalysisResultArgument,
            "-qaProEntitlement",
        ]
        app.launch()
        openStarterDetails()
        app.buttons[UITestIDs.workflowScanStarter].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.analysisResultRoot]
                .firstMatch.waitForExistence(timeout: 8)
        )
        screenshot("analysis_result_before_back")
        tapExplicitBack(UITestIDs.backAnalysisResult, alsoTapVisibleCoordinates: true)
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.scanRoot].firstMatch.waitForExistence(timeout: 5)
        )
        screenshot("analysis_result_after_back_to_scan")
    }

    func testThreeConsecutiveQARunsWithCoordinateBack() throws {
        var proofs: [[String: Any]] = []
        for run in 1...3 {
            app.terminate()
            app.launchArguments = [
                UITestIDs.uiTestingArgument,
                UITestIDs.populatedTimelineArgument,
                "-qaProEntitlement",
            ]
            app.launch()
            assertHome()
            openStarterDetails()
            openTimeline()
            XCTAssertTrue(app.staticTexts["Outcome: Followed"].waitForExistence(timeout: 5))
            let before = "three_run_\(run)_before"
            screenshot(before)
            tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
            assertStarterDetails()
            let after = "three_run_\(run)_after"
            screenshot(after)
            // Outcome must still be intact after returning and re-entering.
            openTimeline()
            XCTAssertTrue(app.staticTexts["Outcome: Followed"].waitForExistence(timeout: 5))
            tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: false)
            proofs.append([
                "run": run,
                "before": before + ".png",
                "after": after + ".png",
                "landed_on": UITestIDs.starterDetailRoot,
                "outcome_preserved": true,
            ])
            tapExplicitBack(UITestIDs.backStarterDetail, alsoTapVisibleCoordinates: true)
            assertHome()
        }
        let reportURL = artifactsRoot.appendingPathComponent("three_run_proof.json")
        let data = try JSONSerialization.data(withJSONObject: proofs, options: [.prettyPrinted])
        try data.write(to: reportURL)
        add(XCTAttachment(contentsOfFile: reportURL))
    }

    func testDebugSchemeLaunchWithoutQAFlag() {
        app.launchArguments = [UITestIDs.uiTestingArgument]
        app.launch()
        assertHome()
        openStarterDetails()
        openTimeline()
        tapExplicitBack(UITestIDs.backTimeline, alsoTapVisibleCoordinates: true)
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
        let link = app.buttons[UITestIDs.workflowTimeline]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestIDs.timelineRoot]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    /// Taps the explicit router Back control via its on-screen center coordinates
    /// (human-visible hit target), not merely an accessibility activate shortcut.
    private func tapExplicitBack(_ identifier: String, alsoTapVisibleCoordinates: Bool) {
        let back = app.buttons[identifier]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Missing back control \(identifier)")
        XCTAssertEqual(back.label, "Back")
        let frame = back.frame
        // Use a small epsilon — CI reports 43.999… for a 44pt toolbar control.
        XCTAssertGreaterThanOrEqual(frame.width, 43.5, "Back hit width \(frame.width)")
        XCTAssertGreaterThanOrEqual(frame.height, 43.5, "Back hit height \(frame.height)")

        // Always use the rendered frame center — this matches the large visible control.
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = alsoTapVisibleCoordinates
    }

    private func swipeBackFromLeftEdge() {
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        coordinate.press(forDuration: 0.05, thenDragTo: end)
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let data = shot.pngRepresentation as Data? {
            let url = artifactsRoot.appendingPathComponent("\(name).png")
            try? data.write(to: url)
        }
    }
}
