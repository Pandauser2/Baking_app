import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import UniformTypeIdentifiers

struct ValidatedImage {
    let image: UIImage
    let jpegData: Data
}

struct ImageValidator {
    private let maxBytes = 8 * 1024 * 1024
    private let minDimension = 512
    private let darkThreshold: CGFloat = 0.16
    private let edgeThreshold: CGFloat = 0.045
    private let ciContext = CIContext()

    func validate(data: Data, contentType: UTType?) throws -> ValidatedImage {
        if let contentType,
           !(contentType.conforms(to: .jpeg) || contentType.conforms(to: .png) || contentType.conforms(to: .heic)) {
            throw AppError.imageValidationFailed("Unsupported format. Use JPEG, PNG, or HEIC.")
        }

        if data.count > maxBytes {
            throw AppError.imageValidationFailed("Image is too large. Please select a smaller photo.")
        }

        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw AppError.imageValidationFailed("Unsupported image file.")
        }

        if cgImage.width < minDimension || cgImage.height < minDimension {
            throw AppError.imageValidationFailed("Image is too small. Minimum size is 512px.")
        }

        let ciImage = CIImage(cgImage: cgImage)
        if meanLuminance(ciImage: ciImage) < darkThreshold {
            throw AppError.imageValidationFailed("Image is too dark. Add more light and retry.")
        }
        if edgeIntensity(ciImage: ciImage) < edgeThreshold {
            throw AppError.imageValidationFailed("Image looks blurry. Hold steady and retake.")
        }

        let resized = resizeForUpload(image: image, maxEdge: 1536)
        guard let jpegData = resized.jpegData(compressionQuality: 0.82) else {
            throw AppError.imageValidationFailed("Could not process this image.")
        }
        if jpegData.count > maxBytes {
            throw AppError.imageValidationFailed("Image is too large after processing. Try a different photo.")
        }

        return ValidatedImage(image: resized, jpegData: jpegData)
    }

    private func meanLuminance(ciImage: CIImage) -> CGFloat {
        let extent = ciImage.extent
        let average = CIFilter.areaAverage()
        average.inputImage = ciImage
        average.extent = extent

        guard let outputImage = average.outputImage else { return 1.0 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }

    private func edgeIntensity(ciImage: CIImage) -> CGFloat {
        let edges = CIFilter.edges()
        edges.inputImage = ciImage
        edges.intensity = 8.0
        guard let edgeImage = edges.outputImage else { return 1.0 }
        return meanLuminance(ciImage: edgeImage)
    }

    private func resizeForUpload(image: UIImage, maxEdge: CGFloat) -> UIImage {
        let original = image.size
        let longestEdge = max(original.width, original.height)
        guard longestEdge > maxEdge else { return image }

        let scale = maxEdge / longestEdge
        let targetSize = CGSize(width: original.width * scale, height: original.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

