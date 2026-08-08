import XCTest
@testable import BakingApp

final class BakeRepositoryDecodingTests: XCTestCase {
    func testBakeJSONDecoding() throws {
        let json = """
        {
          "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "user_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "starter_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
          "baked_at": "2026-08-04T12:00:00.000Z",
          "name": "Tuesday Batard",
          "dough_hydration_percent": 78.5,
          "bulk_fermentation_minutes": 300,
          "final_proof_minutes": 90,
          "mixing_method": "Hand mix",
          "shaping_method": "Batard",
          "oven_temperature_c": 245,
          "baking_time_minutes": 38,
          "result_rating": 5,
          "fermentation_temperature_c": 23.5,
          "fermentation_temperature_source": "dough",
          "retardation_minutes": 600,
          "number_of_folds": 3,
          "steaming_method": "Dutch oven",
          "flour_notes": "Strong white",
          "notes": "Excellent",
          "created_at": "2026-08-04T12:01:00.000Z",
          "updated_at": "2026-08-04T12:01:00.000Z"
        }
        """.data(using: .utf8)!

        let bake = try SupabaseJSONDecoder.make().decode(Bake.self, from: json)
        XCTAssertEqual(bake.name, "Tuesday Batard")
        XCTAssertEqual(bake.resultRating, 5)
        XCTAssertEqual(bake.fermentationTemperatureSource, .dough)
        XCTAssertEqual(bake.doughHydrationPercent, 78.5, accuracy: 0.01)
    }

    func testBakeInsertEncodingKeys() throws {
        let insert = BakeInsert(
            userID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            starterID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            bakedAt: Date(timeIntervalSince1970: 1_700_000_000),
            name: "Encode Test",
            doughHydrationPercent: 70,
            bulkFermentationMinutes: 200,
            finalProofMinutes: 100,
            mixingMethod: "Hand mix",
            shapingMethod: "Boule",
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40,
            resultRating: 3,
            fermentationTemperatureCelsius: 22,
            fermentationTemperatureSource: "room",
            retardationMinutes: nil,
            numberOfFolds: nil,
            steamingMethod: nil,
            flourNotes: nil,
            notes: nil
        )
        let data = try JSONEncoder().encode(insert)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "Encode Test")
        XCTAssertEqual(object?["result_rating"] as? Int, 3)
        XCTAssertEqual(object?["fermentation_temperature_source"] as? String, "room")
        XCTAssertNotNil(object?["user_id"])
        XCTAssertNotNil(object?["starter_id"])
        XCTAssertNil(object?["id"])
    }
}
