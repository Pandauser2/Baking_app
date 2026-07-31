import Foundation
import XCTest
@testable import BakingApp

final class StarterAnalyzeResponseParserTests: XCTestCase {
    func testDecodeWrappedResponseAcceptsValidPayload() throws {
        let wrapped = """
        {
          "result_type": "starter_analysis",
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
        if case .starterAnalysis(let analysis) = result.outcome {
            XCTAssertEqual(analysis.scanType, "starter")
        } else {
            XCTFail("Expected starter_analysis outcome")
        }
    }

    func testDecodeWrappedResponseRejectsUnknownAnalysisField() {
        let wrapped = """
        {
          "result_type": "starter_analysis",
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

    func testDecodeInvalidSubjectAcceptsSafeMessage() throws {
        let wrapped = """
        {
          "result_type": "invalid_subject",
          "reason": "not_starter",
          "message": "This doesn’t appear to be a sourdough starter. Please choose another photo."
        }
        """
        let result = try StarterAnalyzeResponseParser.decode(Data(wrapped.utf8))
        if case .invalidSubject(let reason, let message) = result.outcome {
            XCTAssertEqual(reason, .notStarter)
            XCTAssertEqual(message, "This doesn’t appear to be a sourdough starter. Please choose another photo.")
        } else {
            XCTFail("Expected invalid_subject outcome")
        }
        XCTAssertNil(result.model)
        XCTAssertNil(result.promptVersion)
    }
}

