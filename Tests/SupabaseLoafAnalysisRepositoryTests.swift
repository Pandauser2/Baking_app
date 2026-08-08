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

    func testAnalyzeResponseDecoding() throws {
        let json = """
        {
          "model": "gpt-4o-mini",
          "prompt_version": "v1",
          "analysis": {
            "crumb_score": 70,
            "crust_score": 80,
            "oven_spring_score": 65,
            "overall_score": 72,
            "strengths": ["Open crumb"],
            "improvements": ["Shape"],
            "next_steps": ["More steam"],
            "summary": "Solid bake"
          }
        }
        """.data(using: .utf8)!

        let decoded = try LoafAnalyzeResponseParser.decode(json)
        XCTAssertEqual(decoded.model, "gpt-4o-mini")
        XCTAssertEqual(decoded.analysis.overallScore, 72)
        XCTAssertEqual(decoded.analysis.confidence, 0.72, accuracy: 0.001)
    }

    func testPersistPayloadEncodingKeys() throws {
        let payload = PersistLoafAnalysisPayload(
            bakeID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            storagePath: "user/2026/08/file.jpg",
            model: "gpt-4o-mini",
            promptVersion: "v1",
            confidence: 0.72,
            analysisJSON: LoafAIAnalysis(
                crumbScore: 70,
                crustScore: 80,
                ovenSpringScore: 65,
                overallScore: 72,
                strengths: ["Open crumb"],
                improvements: ["Shape"],
                nextSteps: ["More steam"],
                summary: "Solid bake"
            ),
            renderedExplanation: "Solid bake",
            qualityScore: nil,
            qualityIssue: nil
        )
        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["p_bake_id"])
        XCTAssertEqual(object?["p_storage_path"] as? String, "user/2026/08/file.jpg")
        XCTAssertNotNil(object?["p_analysis_json"])
    }

    func testPersistResponseDecodingSingleAndArray() throws {
        let single = """
        {"scan_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","analysis_id":"cccccccc-cccc-cccc-cccc-cccccccccccc"}
        """.data(using: .utf8)!
        let decodedSingle = try PersistLoafAnalysisResponseDecoder.decodeIDs(single)
        XCTAssertEqual(decodedSingle.scanID.uuidString.lowercased(), "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

        let array = """
        [{"scan_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","analysis_id":"cccccccc-cccc-cccc-cccc-cccccccccccc"}]
        """.data(using: .utf8)!
        let decodedArray = try PersistLoafAnalysisResponseDecoder.decodeIDs(array)
        XCTAssertEqual(decodedArray.analysisID.uuidString.lowercased(), "cccccccc-cccc-cccc-cccc-cccccccccccc")
    }
}
