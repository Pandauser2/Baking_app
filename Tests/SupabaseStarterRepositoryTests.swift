import Foundation
import XCTest
@testable import BakingApp

final class SupabaseStarterRepositoryTests: XCTestCase {
    func testMakeStoragePathUsesStarterScopedPattern() {
        let userID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let starterID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let imageID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let date = Date(timeIntervalSince1970: 1_719_000_000)

        let path = SupabaseStarterRepository.makeStoragePath(
            userID: userID,
            starterID: starterID,
            date: date,
            imageID: imageID
        )

        XCTAssertTrue(path.hasPrefix("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/"))
        XCTAssertTrue(path.hasSuffix("/cccccccc-cccc-cccc-cccc-cccccccccccc.jpg"))
    }
}

