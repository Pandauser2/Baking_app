import XCTest
@testable import BakingApp

final class HomeViewStateResolverTests: XCTestCase {
    func testContentStateIsLoading() {
        let state = HomeViewStateResolver.contentState(isLoading: true, starters: [])
        XCTAssertEqual(state, .loading)
    }

    func testContentStateNoStarter() {
        let state = HomeViewStateResolver.contentState(isLoading: false, starters: [])
        XCTAssertEqual(state, .noStarter)
    }

    func testContentStateStarterAvailable() {
        let starter = makeStarter(name: "Levain")
        let state = HomeViewStateResolver.contentState(isLoading: false, starters: [starter])
        XCTAssertEqual(state, .starterAvailable)
    }

    func testPrimaryActionWithoutStarterIsCreateStarter() {
        let action = HomeViewStateResolver.primaryAction(starters: [])
        XCTAssertEqual(action, .createStarter)
    }

    func testPrimaryActionWithStarterIsLogFeeding() {
        let action = HomeViewStateResolver.primaryAction(starters: [makeStarter(name: "Levain")])
        XCTAssertEqual(action, .logFeeding)
    }

    private func makeStarter(name: String) -> Starter {
        Starter(
            id: UUID(),
            userID: UUID(),
            name: name,
            hydrationPreference: 100,
            createdAt: Date(),
            active: true
        )
    }
}
