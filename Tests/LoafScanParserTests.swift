import XCTest
@testable import BakingApp

final class LoafScanParserTests: XCTestCase {
    func testDecodesWrappedScanResponse() throws {
        let payload = """
        {
          "scan": {
            "id": "70B1333F-4DA3-4A63-9CEE-41A64CD3E48E",
            "user_id": "7D632055-B108-4580-9818-9ED8D0903914",
            "image_path": "user/2026/07/scan.jpg",
            "crumb_score": 70,
            "crust_score": 72,
            "oven_spring_score": 68,
            "overall_score": 71,
            "strengths": ["Good blistering"],
            "improvements": ["More steam"],
            "next_steps": ["Reduce final proof by 10 minutes"],
            "ai_summary": "Balanced loaf.",
            "prompt_version": "v1",
            "created_at": "2026-07-24T16:00:00Z"
          }
        }
        """
        let data = Data(payload.utf8)
        let scan = try LoafScanParser.decodeScanResponse(data)
        XCTAssertEqual(scan.overallScore, 71)
        XCTAssertEqual(scan.promptVersion, "v1")
    }

    func testRejectsMalformedScanResponse() {
        let badPayload = Data("{\"oops\":true}".utf8)
        XCTAssertThrowsError(try LoafScanParser.decodeScanResponse(badPayload))
    }
}

