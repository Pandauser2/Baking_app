import Foundation
import XCTest
import Supabase
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

    func testCreateStarterProfilePayloadHasNoUserIDField() throws {
        let payload = CreateStarterProfilePayload(name: "Levain", hydrationPreference: 100, active: true)
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(json["user_id"])
        XCTAssertNil(json["p_user_id"])
        XCTAssertEqual(json["p_name"] as? String, "Levain")
        XCTAssertEqual(json["p_hydration_preference"] as? Double, 100)
        XCTAssertEqual(json["p_active"] as? Bool, true)
    }

    func testCreateStarterProfilePayloadEncodesNullHydrationWhenMissing() throws {
        let payload = CreateStarterProfilePayload(name: "Levain", hydrationPreference: nil, active: true)
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertTrue(json.keys.contains("p_hydration_preference"))
        XCTAssertTrue(json["p_hydration_preference"] is NSNull)
        XCTAssertEqual(json["p_name"] as? String, "Levain")
        XCTAssertEqual(json["p_active"] as? Bool, true)
    }

    func testFeedingInsertEncodingIncludesAuthenticatedUserID() throws {
        let payload = FeedingLogInsert(
            userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            starterID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            loggedAt: Date(timeIntervalSince1970: 1_719_000_000),
            roomTempC: 24.5,
            flourG: 50,
            waterG: 50,
            starterG: 20,
            notes: "Test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual((json["user_id"] as? String)?.lowercased(), "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual((json["starter_id"] as? String)?.lowercased(), "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    func testSetActiveStarterPayloadEncoding() throws {
        let starterID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let payload = SetActiveStarterPayload(starterID: starterID)
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((json["p_starter_id"] as? String)?.lowercased(), "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    func testRPCStarterDecoderAcceptsArrayResponse() throws {
        let starter = Starter(
            id: UUID(),
            userID: UUID(),
            name: "Levain",
            hydrationPreference: 100,
            createdAt: Date(),
            active: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([starter])
        let decoded = try StarterRPCResponseDecoder.decodeSingleStarter(data)
        XCTAssertEqual(decoded.id, starter.id)
    }

    func testRPCStarterDecoderAcceptsObjectResponse() throws {
        let starter = Starter(
            id: UUID(),
            userID: UUID(),
            name: "Levain",
            hydrationPreference: 100,
            createdAt: Date(),
            active: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(starter)
        let decoded = try StarterRPCResponseDecoder.decodeSingleStarter(data)
        XCTAssertEqual(decoded.id, starter.id)
    }

    func testRPCStarterDecoderRejectsInvalidShape() {
        let invalid = Data("{\"ok\":true}".utf8)
        XCTAssertThrowsError(try StarterRPCResponseDecoder.decodeSingleStarter(invalid)) { error in
            XCTAssertEqual(error as? AppError, .malformedResponse)
        }
    }

    func testErrorMappingSessionMissing() {
        let mapped = RepositoryErrorMapper.map(AuthError.sessionMissing, operation: "save feeding log")
        XCTAssertEqual(mapped, .unknown("Your session has expired. Please sign in again."))
    }

    func testErrorMappingValidationFailure() {
        let mapped = RepositoryErrorMapper.map(
            PostgrestError(code: "23502", message: "null value"),
            operation: "create starter"
        )
        XCTAssertEqual(mapped, .unknown("Some values are invalid. Please review the form and try again."))
    }

    func testErrorMappingPermissionFailure() {
        let mapped = RepositoryErrorMapper.map(
            PostgrestError(code: "42501", message: "new row violates row-level security policy"),
            operation: "create starter"
        )
        XCTAssertEqual(mapped, .unknown("You don't have permission to perform this action."))
    }

    func testErrorMappingDecodingFailure() {
        let mapped = RepositoryErrorMapper.map(
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad json")),
            operation: "load starters"
        )
        XCTAssertEqual(mapped, .unknown("We received an unexpected response from the server. Please try again."))
    }

    func testErrorMappingNetworkFailure() {
        let mapped = RepositoryErrorMapper.map(
            URLError(.notConnectedToInternet),
            operation: "create starter"
        )
        XCTAssertEqual(mapped, .unknown("Network issue detected. Check your connection and try again."))
    }

    func testErrorMappingUnknownFailure() {
        let mapped = RepositoryErrorMapper.map(TestError.insertFailed, operation: "create starter")
        XCTAssertEqual(mapped, .unknown("Something went wrong while trying to create starter. Please try again."))
    }

    func testRPCCreatePayloadPreventsUserIDInjectionFromUI() throws {
        let payload = CreateStarterProfilePayload(name: "Levain", hydrationPreference: nil, active: false)
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["user_id"])
        XCTAssertNil(json["p_user_id"])
    }

    func testAnalyzeErrorMappingAuthInvalid() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 401,
            data: makeAnalyzeErrorBody(code: "AUTH_INVALID", message: "Authentication is invalid.")
        )
        XCTAssertEqual(error, .unknown("Your session is invalid. Please sign in again and retry analysis."))
    }

    func testAnalyzeErrorMappingStarterNotFound() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 404,
            data: makeAnalyzeErrorBody(code: "STARTER_NOT_FOUND", message: "Starter not found.")
        )
        XCTAssertEqual(error, .unknown("Starter not found. Refresh your starters and try again."))
    }

    func testAnalyzeErrorMappingImageDownloadFailed() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 400,
            data: makeAnalyzeErrorBody(code: "IMAGE_DOWNLOAD_FAILED", message: "Could not download image.")
        )
        XCTAssertEqual(error, .unknown("We couldn't read the uploaded image. Please choose another photo and retry."))
    }

    func testAnalyzeErrorMappingImageInvalid() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 400,
            data: makeAnalyzeErrorBody(code: "IMAGE_INVALID", message: "Image failed validation.")
        )
        XCTAssertEqual(error, .unknown("The uploaded image was rejected. Retake the photo and try again."))
    }

    func testAnalyzeErrorMappingProviderAuth() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 502,
            data: makeAnalyzeErrorBody(code: "PROVIDER_AUTH", message: "Provider auth failed.")
        )
        XCTAssertEqual(error, .unknown("Analysis provider authentication failed. Please try again shortly."))
    }

    func testAnalyzeErrorMappingProviderQuota() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 503,
            data: makeAnalyzeErrorBody(code: "PROVIDER_QUOTA", message: "Quota exceeded.")
        )
        XCTAssertEqual(error, .unknown("Analysis is temporarily unavailable due to provider quota limits. Please try again later."))
    }

    func testAnalyzeErrorMappingProviderRateLimit() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 429,
            data: makeAnalyzeErrorBody(code: "PROVIDER_RATE_LIMIT", message: "Rate limited.")
        )
        XCTAssertEqual(error, .unknown("Analysis is temporarily rate-limited. Please wait a moment and retry."))
    }

    func testAnalyzeErrorMappingProviderTimeout() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 504,
            data: makeAnalyzeErrorBody(code: "PROVIDER_TIMEOUT", message: "Timed out.")
        )
        XCTAssertEqual(error, .unknown("Analysis timed out. Please retry."))
    }

    func testAnalyzeErrorMappingProviderResponseInvalid() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 502,
            data: makeAnalyzeErrorBody(code: "PROVIDER_RESPONSE_INVALID", message: "Invalid provider response.")
        )
        XCTAssertEqual(error, .unknown("The analysis provider returned an invalid response. Please retry with another photo."))
    }

    func testAnalyzeErrorMappingInternalErrorUsesSafeMessage() {
        let error = StarterAnalyzeHTTPErrorMapper.map(
            statusCode: 500,
            data: makeAnalyzeErrorBody(code: "INTERNAL_ERROR", message: "Analysis failed due to an unexpected internal error.")
        )
        XCTAssertEqual(error, .unknown("Analysis failed due to an unexpected internal error."))
    }

    func testAnalyzeErrorMappingInvalidBodyFallsBackToGenericAnalysisFailure() {
        let error = StarterAnalyzeHTTPErrorMapper.map(statusCode: 500, data: Data("{}".utf8))
        XCTAssertEqual(error, .analysisFailed)
    }

    func testPersistResponseDecoderAcceptsArrayShape() throws {
        let ids = PersistedStarterAnalysisIDs(scanID: UUID(), analysisID: UUID(), recommendationID: UUID())
        let data = try JSONEncoder().encode([ids])
        let decoded = try PersistStarterAnalysisResponseDecoder.decodeIDs(data)
        XCTAssertEqual(decoded, ids)
    }

    func testPersistResponseDecoderAcceptsObjectShape() throws {
        let ids = PersistedStarterAnalysisIDs(scanID: UUID(), analysisID: UUID(), recommendationID: UUID())
        let data = try JSONEncoder().encode(ids)
        let decoded = try PersistStarterAnalysisResponseDecoder.decodeIDs(data)
        XCTAssertEqual(decoded, ids)
    }

    func testPersistErrorMappingAuthFailed() {
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 401,
            data: Data(),
            requestID: "req-1"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_AUTH_FAILED")
    }

    func testPersistErrorMappingStarterNotFound() throws {
        let payload: [String: Any] = [
            "code": "P0001",
            "message": "Starter not found for user",
            "details": "",
            "hint": ""
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 400,
            data: data,
            requestID: "req-2"
        )
        XCTAssertEqual(mapped.errorCode, "STARTER_NOT_FOUND")
    }

    func testPersistErrorMappingValidationFailed() throws {
        let payload: [String: Any] = [
            "code": "23514",
            "message": "Confidence must be between 0 and 1",
            "details": "",
            "hint": ""
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 400,
            data: data,
            requestID: "req-3"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_VALIDATION_FAILED")
    }

    func testPersistErrorMappingProductionPGRST202SignatureMismatch() throws {
        let fixture: [String: Any?] = [
            "code": "PGRST202",
            "message": "Could not find function public.persist_starter_analysis(...)",
            "details": "Searched for the function in the schema cache.",
            "hint": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture.compactMapValues { $0 })
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 404,
            data: data,
            requestID: "req-prod-fixture"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_VALIDATION_FAILED")
        XCTAssertEqual(mapped.message, "The save request format was invalid.")
    }

    func testPersistPayloadIncludesNilQualityIssueAndScore() throws {
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
            starterID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            storagePath: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/2026/07/file.jpg",
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

        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertTrue(json.keys.contains("p_quality_score"))
        XCTAssertTrue(json.keys.contains("p_quality_issue"))
        XCTAssertTrue(json["p_quality_score"] is NSNull)
        XCTAssertTrue(json["p_quality_issue"] is NSNull)
    }

    func testPersistErrorMappingConflict() throws {
        let payload: [String: Any] = [
            "code": "23505",
            "message": "duplicate key value violates unique constraint",
            "details": "",
            "hint": ""
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 409,
            data: data,
            requestID: "req-4"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_CONFLICT")
    }

    func testPersistErrorMappingDatabaseError() {
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 500,
            data: Data("{}".utf8),
            requestID: "req-5"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_DATABASE_ERROR")
    }

    func testPersistErrorMappingResponseInvalidFallback() {
        let mapped = PersistStarterAnalysisHTTPErrorMapper.map(
            statusCode: 418,
            data: Data("{}".utf8),
            requestID: "req-6"
        )
        XCTAssertEqual(mapped.errorCode, "PERSIST_RESPONSE_INVALID")
    }

    private func makeAnalyzeErrorBody(code: String, message: String) -> Data {
        let payload: [String: Any] = [
            "error_code": code,
            "message": message,
            "request_id": UUID().uuidString.lowercased()
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

private enum TestError: Error, Equatable {
    case insertFailed
}

