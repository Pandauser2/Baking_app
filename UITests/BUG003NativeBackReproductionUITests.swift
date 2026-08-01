import XCTest

/// Documents the f029b09 native-back failure captured under artifacts/e2e/bug003/pre_fix.
/// This test does not re-assert the old failure against the fixed build.
final class BUG003NativeBackReproductionUITests: XCTestCase {
    func testPreFixNativeBackEvidenceExists() throws {
        let artifacts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/bug003_pre_fix", isDirectory: true)
        let reportURL = artifacts.appendingPathComponent("native_back_repro.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path), "Missing pre-fix repro JSON")
        let data = try Data(contentsOf: reportURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["commit"] as? String, "f029b09")
        XCTAssertEqual(json["native_back_failed"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.appendingPathComponent("before_native_back.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.appendingPathComponent("after_native_back.png").path))
    }
}
