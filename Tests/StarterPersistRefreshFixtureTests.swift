import Foundation
import XCTest
@testable import BakingApp

final class StarterPersistRefreshFixtureTests: XCTestCase {
    func testDecodeRPCArrayResponseFixture() throws {
        let data = try fixture("persist_rpc_array")
        let ids = try PersistStarterAnalysisResponseDecoder.decodeIDs(data)
        XCTAssertNotNil(ids.scanID)
        XCTAssertNotNil(ids.analysisID)
        XCTAssertNotNil(ids.recommendationID)
    }

    func testDecodeRPCObjectResponseFixture() throws {
        let data = try fixture("persist_rpc_object")
        let ids = try PersistStarterAnalysisResponseDecoder.decodeIDs(data)
        XCTAssertNotNil(ids.scanID)
        XCTAssertNotNil(ids.analysisID)
        XCTAssertNotNil(ids.recommendationID)
    }

    func testPGRST202FixtureMapsToValidationFailed() throws {
        let data = try fixture("pgrst202")
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 404,
            data: data,
            requestID: "fixture-req"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_VALIDATION_FAILED")
    }

    func testPersistPayloadIncludesNilOptionalParameters() throws {
        let analysis = StarterAIResponse(
            scanType: "starter",
            observations: ["Bubbles"],
            diagnosis: ["Active"],
            confidence: 0.8,
            nextSteps: [StarterAIResponse.NextStep(instruction: "Feed now", timeWindowHours: 12)],
            humanExplanation: "Looks active.",
            riskFlags: [],
            compareToPrevious: StarterAIResponse.CompareToPrevious(changed: true, explanation: "Improved rise."),
            starterState: "active"
        )
        let payload = PersistStarterAnalysisPayload(
            starterID: UUID(),
            storagePath: "user/starter/2026/07/file.jpg",
            qualityScore: nil,
            qualityIssue: nil,
            model: "gpt-4o-mini",
            promptVersion: "v1",
            confidence: analysis.confidence,
            analysisJSON: analysis,
            renderedExplanation: analysis.humanExplanation,
            stateLabel: analysis.starterState,
            recommendation: analysis.nextSteps[0].instruction,
            dueHours: analysis.nextSteps[0].timeWindowHours
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertTrue(json["p_quality_score"] is NSNull)
        XCTAssertTrue(json["p_quality_issue"] is NSNull)
    }

    func testDecodeStarterStateFixtureWithFractionalTimestamp() throws {
        let data = try fixture("starter_states_array")
        let states = try SupabaseJSONDecoder.make().decode([StarterState].self, from: data)
        XCTAssertEqual(states.count, 1)
        XCTAssertFalse(states[0].stateLabel.isEmpty)
    }

    func testDecodeRecommendationFixtureWithFractionalTimestamp() throws {
        let data = try fixture("recommendation_array")
        let recommendations = try SupabaseJSONDecoder.make().decode([Recommendation].self, from: data)
        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations[0].outcome, "unknown")
        XCTAssertNotNil(recommendations[0].dueAt)
        XCTAssertNil(recommendations[0].completedAt)
    }

    func testDecodeTimelineNestedObjectAndArrayRelationships() throws {
        let data = try fixture("timeline_nested")
        let rows = try TimelineRowDecoder.decodeRows(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].analyses.count, 1)
        XCTAssertEqual(rows[0].recommendations.count, 1)
        XCTAssertEqual(rows[0].recommendations[0].recommendation, "Feed now")
    }

    func testDecodeTimelineNullAndEmptyNestedRelationships() throws {
        let data = try fixture("timeline_null_nested")
        let rows = try TimelineRowDecoder.decodeRows(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].analyses.isEmpty)
        XCTAssertTrue(rows[0].recommendations.isEmpty)
    }

    func testFractionalAndNonFractionalTimestampsDecode() throws {
        let payload = """
        [{"starter_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","user_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","state_label":"active","updated_from_scan_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","updated_at":"2026-07-31T16:44:05.421029+00:00"}]
        """.data(using: .utf8)!
        let states = try SupabaseJSONDecoder.make().decode([StarterState].self, from: payload)
        XCTAssertEqual(states.count, 1)

        let plain = """
        [{"starter_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","user_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","state_label":"active","updated_from_scan_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","updated_at":"2026-07-31T16:44:05Z"}]
        """.data(using: .utf8)!
        let statesPlain = try SupabaseJSONDecoder.make().decode([StarterState].self, from: plain)
        XCTAssertEqual(statesPlain.count, 1)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: StarterPersistRefreshFixtureTests.self).url(forResource: name, withExtension: "json")
            ?? Bundle(for: StarterPersistRefreshFixtureTests.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }
}
