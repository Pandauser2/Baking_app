import Foundation
import XCTest
@testable import BakingApp

final class StarterAnalyzeResponseParserTests: XCTestCase {
    func testDecodeWrappedResponseAcceptsValidPayload() throws {
        let wrapped = """
        {
          "prompt_version": "v1",
          "model": "gpt-4o-mini",
          "analysis": {
            "scan_type": "starter",
            "observations": ["Visible bubbles on surface"],
            "diagnosis": ["active"],
            "confidence": 0.81,
            "next_steps": [{"instruction": "Feed now", "time_window_hours": 12}],
            "human_explanation": "Surface activity is strong.",
            "risk_flags": [],
            "compare_to_previous": {"changed": true, "explanation": "More bubble density."},
            "starter_state": "active"
          }
        }
        """
        let result = try StarterAnalyzeResponseParser.decode(Data(wrapped.utf8))
        XCTAssertEqual(result.model, "gpt-4o-mini")
        XCTAssertEqual(result.promptVersion, "v1")
        XCTAssertEqual(result.analysis.scanType, "starter")
    }

    func testDecodeWrappedResponseRejectsUnknownAnalysisField() {
        let wrapped = """
        {
          "prompt_version": "v1",
          "model": "gpt-4o-mini",
          "analysis": {
            "scan_type": "starter",
            "observations": ["Visible bubbles on surface"],
            "diagnosis": ["active"],
            "confidence": 0.81,
            "next_steps": [{"instruction": "Feed now", "time_window_hours": 12}],
            "human_explanation": "Surface activity is strong.",
            "risk_flags": [],
            "compare_to_previous": {"changed": true, "explanation": "More bubble density."},
            "starter_state": "active",
            "unexpected": true
          }
        }
        """
        XCTAssertThrowsError(try StarterAnalyzeResponseParser.decode(Data(wrapped.utf8)))
    }
}

