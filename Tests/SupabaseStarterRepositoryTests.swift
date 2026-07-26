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

    func testStarterInsertEncodingIncludesAuthenticatedUserID() throws {
        let payload = StarterInsert(
            userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Levain",
            hydrationPreference: 100,
            active: true
        )
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual((json["user_id"] as? String)?.lowercased(), "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual(json["name"] as? String, "Levain")
        XCTAssertEqual(json["active"] as? Bool, true)
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

    func testCreateStarterWithActivationDoesNotDeactivateWhenInsertFails() async {
        var deactivateCalled = false
        do {
            _ = try await SupabaseStarterRepository.createStarterWithActivation(
                active: true,
                insert: {
                    throw TestError.insertFailed
                },
                deactivateOthers: { _ in
                    deactivateCalled = true
                }
            )
            XCTFail("Expected insert failure")
        } catch {
            XCTAssertEqual(error as? TestError, .insertFailed)
        }
        XCTAssertFalse(deactivateCalled)
    }

    func testCreateStarterWithActivationDeactivatesAfterSuccessfulInsert() async throws {
        let createdStarter = Starter(
            id: UUID(),
            userID: UUID(),
            name: "Levain",
            hydrationPreference: 100,
            createdAt: Date(),
            active: true
        )
        var deactivatedStarterID: UUID?
        let result = try await SupabaseStarterRepository.createStarterWithActivation(
            active: true,
            insert: { createdStarter },
            deactivateOthers: { id in
                deactivatedStarterID = id
            }
        )

        XCTAssertEqual(result.id, createdStarter.id)
        XCTAssertEqual(deactivatedStarterID, createdStarter.id)
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

    func testUserIDComesFromRepositoryPayloadNotUIInput() throws {
        let payload = StarterInsert(
            userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Levain",
            hydrationPreference: nil,
            active: false
        )
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(json["user_id"])
    }
}

private enum TestError: Error, Equatable {
    case insertFailed
}

