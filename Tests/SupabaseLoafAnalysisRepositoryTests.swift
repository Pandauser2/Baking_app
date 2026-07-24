import Foundation
import XCTest
@testable import BakingApp

final class SupabaseLoafAnalysisRepositoryTests: XCTestCase {
    func testStoragePathFormat() {
        let userID = UUID(uuidString: "7D632055-B108-4580-9818-9ED8D0903914")!
        let imageID = UUID(uuidString: "70B1333F-4DA3-4A63-9CEE-41A64CD3E48E")!
        let date = ISO8601DateFormatter().date(from: "2026-07-24T16:00:00Z")!

        let path = SupabaseLoafAnalysisRepository.makeStoragePath(
            userID: userID,
            date: date,
            imageID: imageID
        )

        XCTAssertEqual(path, "7d632055-b108-4580-9818-9ed8d0903914/2026/07/70b1333f-4da3-4a63-9cee-41a64cd3e48e.jpg")
    }
}

