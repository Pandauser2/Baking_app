import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import BakingApp

@MainActor
final class ImageValidatorTests: XCTestCase {
    func testRejectsUnsupportedFormat() {
        let validator = ImageValidator()
        let data = Data("not-an-image".utf8)
        XCTAssertThrowsError(
            try validator.validate(data: data, contentType: .pdf)
        )
    }

    func testRejectsTooSmallImage() {
        let validator = ImageValidator()
        let image = solidImage(color: .white, size: CGSize(width: 300, height: 300))
        let data = image.jpegData(compressionQuality: 1.0)!
        XCTAssertThrowsError(
            try validator.validate(data: data, contentType: .jpeg)
        )
    }

    func testRejectsDarkImage() {
        let validator = ImageValidator()
        let image = solidImage(color: .black, size: CGSize(width: 900, height: 900))
        let data = image.jpegData(compressionQuality: 1.0)!
        XCTAssertThrowsError(
            try validator.validate(data: data, contentType: .jpeg)
        )
    }

    private func solidImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

