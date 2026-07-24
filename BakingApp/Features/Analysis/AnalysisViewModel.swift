import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var selectedItem: PhotosPickerItem?
    @Published var latestResult: LoafScan?
    @Published var history: [LoafScan] = []
    @Published var isUploading = false
    @Published var isAnalyzing = false
    @Published var progressMessage: String?
    @Published var errorMessage: String?

    private(set) var latestImagePath: String?

    private let repository: LoafAnalysisRepository
    private let validator: ImageValidator
    private let analytics: AnalyticsTracking

    init(
        repository: LoafAnalysisRepository,
        validator: ImageValidator = ImageValidator(),
        analytics: AnalyticsTracking
    ) {
        self.repository = repository
        self.validator = validator
        self.analytics = analytics
    }

    func handleSelectedPhotoItem() async {
        guard let selectedItem else { return }
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self) else {
                throw AppError.imageValidationFailed("Could not read selected image.")
            }
            let contentType = selectedItem.supportedContentTypes.first
            let validated = try validator.validate(data: data, contentType: contentType)
            selectedImage = validated.image
            analytics.track(.photoSelected)
            errorMessage = nil
        } catch let appError as AppError {
            errorMessage = appError.errorDescription
        } catch {
            errorMessage = AppError.imageValidationFailed("Could not process selected image.").errorDescription
        }
    }

    func handleCapturedImage(_ image: UIImage) {
        do {
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                throw AppError.imageValidationFailed("Could not process camera image.")
            }
            let validated = try validator.validate(data: data, contentType: .jpeg)
            selectedImage = validated.image
            analytics.track(.photoSelected)
            errorMessage = nil
        } catch let appError as AppError {
            errorMessage = appError.errorDescription
        } catch {
            errorMessage = AppError.imageValidationFailed("Could not process selected image.").errorDescription
        }
    }

    func analyze(userID: UUID) async {
        guard let selectedImage else {
            errorMessage = "Please select or capture a loaf photo first."
            return
        }

        do {
            guard let rawData = selectedImage.jpegData(compressionQuality: 0.9) else {
                throw AppError.imageValidationFailed("Could not process selected image.")
            }
            let validated = try validator.validate(data: rawData, contentType: .jpeg)
            analytics.track(.uploadStarted)
            isUploading = true
            progressMessage = "Uploading photo..."
            let imagePath = try await repository.uploadImage(validated.jpegData, userID: userID)
            latestImagePath = imagePath
            isUploading = false
            analytics.track(.uploadCompleted)

            isAnalyzing = true
            progressMessage = "Analyzing loaf..."
            analytics.track(.analysisStarted)
            let result = try await repository.analyzeLoaf(imagePath: imagePath, promptVersion: "v1")
            latestResult = result
            isAnalyzing = false
            progressMessage = nil
            analytics.track(.analysisCompleted)
            errorMessage = nil
        } catch let appError as AppError {
            isUploading = false
            isAnalyzing = false
            progressMessage = nil
            errorMessage = appError.errorDescription
            analytics.track(.analysisFailed)
        } catch {
            isUploading = false
            isAnalyzing = false
            progressMessage = nil
            errorMessage = AppError.analysisFailed.errorDescription
            analytics.track(.analysisFailed)
        }
    }

    func loadHistory() async {
        do {
            history = try await repository.fetchHistory()
        } catch let appError as AppError {
            errorMessage = appError.errorDescription
        } catch {
            errorMessage = AppError.unknown("Could not load scan history.").errorDescription
        }
    }

    func signedImageURL(path: String) async -> URL? {
        do {
            return try await repository.signedImageURL(path: path, expiresIn: 1800)
        } catch {
            return nil
        }
    }
}

