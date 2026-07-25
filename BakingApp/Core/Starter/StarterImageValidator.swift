import CoreImage
import UIKit

struct StarterValidatedImage {
    let jpegData: Data
    let qualityScore: Double
    let qualityIssue: String?
    let pixelSize: CGSize
}

struct StarterImageValidator {
    let minimumDimension: CGFloat
    let maxBytes: Int
    let targetMaxDimension: CGFloat

    init(minimumDimension: CGFloat = 512, maxBytes: Int = 5_000_000, targetMaxDimension: CGFloat = 1600) {
        self.minimumDimension = minimumDimension
        self.maxBytes = maxBytes
        self.targetMaxDimension = targetMaxDimension
    }

    func validate(data: Data) throws -> StarterValidatedImage {
        guard let sourceImage = UIImage(data: data) else {
            throw AppError.imageValidationFailed("Image file is not decodable.")
        }

        guard let mime = detectMimeType(data), mime == "image/jpeg" || mime == "image/png" else {
            throw AppError.imageValidationFailed("Only JPEG or PNG images are supported.")
        }

        let normalized = resizeIfNeeded(sourceImage)
        let dimensions = CGSize(width: normalized.cgImage?.width ?? Int(normalized.size.width),
                                height: normalized.cgImage?.height ?? Int(normalized.size.height))
        guard dimensions.width >= minimumDimension, dimensions.height >= minimumDimension else {
            throw AppError.imageValidationFailed("Image must be at least \(Int(minimumDimension))x\(Int(minimumDimension)) pixels.")
        }

        guard var jpegData = normalized.jpegData(compressionQuality: 0.9) else {
            throw AppError.imageValidationFailed("Image could not be normalized.")
        }
        if jpegData.count > maxBytes {
            guard let compressed = normalized.jpegData(compressionQuality: 0.75), compressed.count <= maxBytes else {
                throw AppError.imageValidationFailed("Image is too large to upload.")
            }
            jpegData = compressed
        }

        let darkness = darknessScore(image: normalized)
        let blur = blurScore(image: normalized)
        var quality = 1.0
        var issue: String?
        if darkness < 0.18 {
            quality -= 0.4
            issue = "Image seems too dark."
        }
        if blur > 0.8 {
            quality -= 0.3
            issue = issue == nil ? "Image appears blurry." : "\(issue!) It also appears blurry."
        }
        quality = max(0, min(1, quality))

        return StarterValidatedImage(
            jpegData: jpegData,
            qualityScore: quality,
            qualityIssue: issue,
            pixelSize: dimensions
        )
    }

    private func detectMimeType(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return nil
    }

    private func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let maxDimension = max(width, height)
        guard maxDimension > targetMaxDimension else { return image }

        let scale = targetMaxDimension / maxDimension
        let newSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func darknessScore(image: UIImage) -> Double {
        guard
            let ciImage = CIImage(image: image),
            let filter = CIFilter(name: "CIAreaAverage")
        else {
            return 0.5
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let output = filter.outputImage else { return 0.5 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        return (r + g + b) / 3.0
    }

    private func blurScore(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        let width = cgImage.width
        let height = cgImage.height
        guard
            let provider = cgImage.dataProvider,
            let pixelData = provider.data
        else {
            return 0.0
        }

        let data = CFDataGetBytePtr(pixelData)
        let bytesPerPixel = 4
        let rowStride = width * bytesPerPixel
        var edgeMagnitudeTotal: Double = 0
        var samples = 0
        let step = max(1, min(width, height) / 80)
        if width <= step || height <= step { return 0.0 }

        for y in Swift.stride(from: step, to: height - step, by: step) {
            for x in Swift.stride(from: step, to: width - step, by: step) {
                let center = luminance(data, x: x, y: y, stride: rowStride)
                let right = luminance(data, x: x + step, y: y, stride: rowStride)
                let down = luminance(data, x: x, y: y + step, stride: rowStride)
                edgeMagnitudeTotal += abs(center - right) + abs(center - down)
                samples += 1
            }
        }
        guard samples > 0 else { return 0.0 }
        let averageEdge = edgeMagnitudeTotal / Double(samples)
        // Lower edge contrast implies more blur; convert to [0,1] blur score.
        return max(0, min(1, 1 - (averageEdge / 35.0)))
    }

    private func luminance(_ data: UnsafePointer<UInt8>?, x: Int, y: Int, stride: Int) -> Double {
        guard let data else { return 0 }
        let offset = y * stride + x * 4
        let r = Double(data[offset])
        let g = Double(data[offset + 1])
        let b = Double(data[offset + 2])
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

