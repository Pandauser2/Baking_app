import UIKit
import XCTest
@testable import BakingApp

final class StarterImageValidatorTests: XCTestCase {
    func testRejectsTooSmallImage() {
        let validator = StarterImageValidator(minimumDimension: 512, maxBytes: 5_000_000, targetMaxDimension: 1600)
        let image = solidImage(size: CGSize(width: 400, height: 400))
        let data = image.pngData()!
        XCTAssertThrowsError(try validator.validate(data: data))
    }

    func testReturnsQualityIssueForDarkImage() throws {
        let validator = StarterImageValidator(minimumDimension: 512, maxBytes: 5_000_000, targetMaxDimension: 1600)
        let image = solidImage(size: CGSize(width: 800, height: 800), color: .black)
        let result = try validator.validate(data: image.pngData()!)
        XCTAssertNotNil(result.qualityIssue)
        XCTAssertLessThan(result.qualityScore, 1.0)
    }

    private func solidImage(size: CGSize, color: UIColor = .white) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

