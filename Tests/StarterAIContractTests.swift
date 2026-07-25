import Foundation
import XCTest
@testable import BakingApp

final class StarterAIContractTests: XCTestCase {
    func testDecodeStrictAcceptsValidPayload() throws {
        let data = try JSONSerialization.data(withJSONObject: validPayload())
        let decoded = try StarterAIContractValidator.decodeStrict(data)
        XCTAssertEqual(decoded.scanType, "starter")
        XCTAssertEqual(decoded.nextSteps.count, 1)
    }

    func testDecodeStrictRejectsUnknownField() throws {
        var payload = validPayload()
        payload["unknown"] = "value"
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try StarterAIContractValidator.decodeStrict(data))
    }

    func testDecodeStrictRejectsInvalidConfidence() throws {
        var payload = validPayload()
        payload["confidence"] = 1.2
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try StarterAIContractValidator.decodeStrict(data))
    }

    func testDecodeStrictRejectsMultipleRecommendations() throws {
        var payload = validPayload()
        payload["next_steps"] = [
            ["instruction": "Feed", "time_window_hours": 12],
            ["instruction": "Wait", "time_window_hours": 6]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try StarterAIContractValidator.decodeStrict(data))
    }

    private func validPayload() -> [String: Any] {
        [
            "scan_type": "starter",
            "observations": ["Visible bubbles"],
            "diagnosis": ["active"],
            "confidence": 0.75,
            "next_steps": [
                ["instruction": "Feed at 1:2:2", "time_window_hours": 12]
            ],
            "human_explanation": "Looks active after the last feeding.",
            "risk_flags": [],
            "compare_to_previous": ["changed": true, "explanation": "More bubbles than prior scan"],
            "starter_state": "active"
        ]
    }
}

