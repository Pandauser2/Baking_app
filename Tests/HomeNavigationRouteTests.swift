import SwiftUI
import XCTest
@testable import BakingApp

final class HomeNavigationRouteTests: XCTestCase {
    func testRouteHashStabilityForSameStarter() {
        let id = UITestingBootstrap.starterID
        XCTAssertEqual(
            HomeNavigationRoute.timeline(id),
            HomeNavigationRoute.timeline(id)
        )
        XCTAssertNotEqual(
            HomeNavigationRoute.timeline(id),
            HomeNavigationRoute.starterDetail(id)
        )
    }

    func testNavigationPathAppendAndPopPreservesOrder() {
        var path = NavigationPath()
        let starterID = UITestingBootstrap.starterID
        path.append(HomeNavigationRoute.starterDetail(starterID))
        path.append(HomeNavigationRoute.timeline(starterID))
        XCTAssertEqual(path.count, 2)

        path.removeLast()
        XCTAssertEqual(path.count, 1)

        path.append(HomeNavigationRoute.feedingHistory(starterID))
        path.append(HomeNavigationRoute.scanStarter(starterID))
        path.append(HomeNavigationRoute.analysisResult(starterID))
        XCTAssertEqual(path.count, 4)

        path.removeLast(3)
        XCTAssertEqual(path.count, 1)
        path.removeLast()
        XCTAssertEqual(path.count, 0)
    }

    func testUITestingBootstrapExposesFixtureStarter() {
        let starter = UITestingBootstrap.makeStarter()
        XCTAssertEqual(starter.id, UITestingBootstrap.starterID)
        XCTAssertTrue(starter.active)
        XCTAssertEqual(UITestingBootstrap.makeTimelineItem().recommendation?.outcome, "followed")
    }
}
