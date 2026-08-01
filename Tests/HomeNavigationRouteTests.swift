import XCTest
@testable import BakingApp

@MainActor
final class HomeNavigationRouteTests: XCTestCase {
    func testRouterPushPopRemovesExactlyOneRoute() {
        let router = HomeNavigationRouter()
        let starterID = UITestingBootstrap.starterID

        router.push(.starterDetail(starterID), screen: "test")
        router.push(.timeline(starterID), screen: "test")
        XCTAssertEqual(router.pathCount, 2)
        XCTAssertEqual(router.topRoute, .timeline(starterID))

        router.pop(screen: "Timeline")
        XCTAssertEqual(router.pathCount, 1)
        XCTAssertEqual(router.topRoute, .starterDetail(starterID))

        router.pop(screen: "StarterDetail")
        XCTAssertEqual(router.pathCount, 0)
        XCTAssertFalse(router.canPop)
    }

    func testRouterIgnoresDuplicateTopPush() {
        let router = HomeNavigationRouter()
        let starterID = UITestingBootstrap.starterID
        router.push(.timeline(starterID), screen: "test")
        router.push(.timeline(starterID), screen: "test")
        XCTAssertEqual(router.pathCount, 1)
    }

    func testRouterPopOnEmptyIsNoOp() {
        let router = HomeNavigationRouter()
        router.pop(screen: "Home")
        XCTAssertEqual(router.pathCount, 0)
    }

    func testPathBindingSwipePopSyncsRouter() {
        let router = HomeNavigationRouter()
        let starterID = UITestingBootstrap.starterID
        router.push(.starterDetail(starterID), screen: "test")
        router.push(.timeline(starterID), screen: "test")

        router.pathBinding.wrappedValue = [.starterDetail(starterID)]
        XCTAssertEqual(router.pathCount, 1)
        XCTAssertEqual(router.topRoute, .starterDetail(starterID))
    }

    func testWorkflowRouteCoverage() {
        let id = UITestingBootstrap.starterID
        let routes: [HomeNavigationRoute] = [
            .starterList,
            .starterDetail(id),
            .feedingLog(id),
            .feedingHistory(id),
            .scanStarter(id),
            .analysisResult(id),
            .timeline(id),
        ]
        XCTAssertEqual(Set(routes).count, routes.count)
    }
}
