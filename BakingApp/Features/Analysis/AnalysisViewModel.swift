import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var selectedItem: PhotosPickerItem?
    @Published var latestResult: LoafAnalyzeResult?
    @Published var latestPersistedIDs: PersistedLoafAnalysisIDs?
    @Published var comparison: LoafComparisonPresentation?
    @Published var bakeAnalyses: [CanonicalLoafAnalysis] = []
    @Published var history: [LoafScan] = []
    @Published var isUploading = false
    @Published var isAnalyzing = false
    @Published var isPersisting = false
    @Published var progressMessage: String?
    @Published var errorMessage: String?
    @Published var didSaveBaseline = false

    private(set) var latestImagePath: String?
    private(set) var currentBake: Bake?
    private(set) var previousRef: PreviousBakeRef?
    private(set) var previousAnalysis: CanonicalLoafAnalysis?

    private let bakeID: UUID?
    private let repository: LoafAnalysisRepository
    private let bakeRepository: BakeRepository?
    private let validator: ImageValidator
    private let analytics: AnalyticsTracking
    private var isProUser: Bool

    init(
        repository: LoafAnalysisRepository,
        bakeID: UUID? = nil,
        bakeRepository: BakeRepository? = nil,
        isProUser: Bool = false,
        validator: ImageValidator = ImageValidator(),
        analytics: AnalyticsTracking
    ) {
        self.repository = repository
        self.bakeID = bakeID
        self.bakeRepository = bakeRepository
        self.isProUser = isProUser
        self.validator = validator
        self.analytics = analytics
    }

    func updateProStatus(_ isPro: Bool) {
        isProUser = isPro
    }

    func prepareBakeContext() async {
        guard let bakeID, let bakeRepository else { return }
        do {
            let bake = try await bakeRepository.fetchBake(bakeID: bakeID)
            currentBake = bake
            let allBakes = try await bakeRepository.listBakes()
            previousRef = PreviousBakeSelector.select(current: bake, from: allBakes)
            if let previous = previousRef {
                let analyses = try await repository.fetchLoafAnalyses(forBakeID: previous.bake.id)
                previousAnalysis = analyses.sorted { $0.createdAt > $1.createdAt }.first
            } else {
                previousAnalysis = nil
            }
            bakeAnalyses = try await repository.fetchLoafAnalyses(forBakeID: bakeID)
            if let existing = bakeAnalyses.sorted(by: { $0.createdAt > $1.createdAt }).first {
                if let snapshot = existing.analysis.comparison {
                    comparison = LoafComparisonEngine.presentation(
                        from: snapshot,
                        analysis: existing.analysis,
                        previousBakeName: previousRef?.bake.name
                    )
                } else {
                    // Legacy rows without snapshot: do not silently recompute against live journal.
                    comparison = nil
                }
                latestResult = LoafAnalyzeResult(
                    model: existing.model,
                    promptVersion: existing.promptVersion,
                    analysis: existing.analysis
                )
                latestImagePath = existing.storagePath
                latestPersistedIDs = PersistedLoafAnalysisIDs(
                    scanID: existing.scanID,
                    analysisID: existing.analysisID
                )
            }
            errorMessage = nil
        } catch let appError as AppError {
            errorMessage = appError.errorDescription
        } catch {
            errorMessage = AppError.unknown("Could not load bake context.").errorDescription
        }
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
        guard isProUser else {
            errorMessage = AppError.subscriptionRequired.errorDescription
            return
        }
        guard let selectedImage else {
            errorMessage = "Please select or capture a loaf photo first."
            return
        }

        do {
            if currentBake == nil {
                await prepareBakeContext()
            }
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

            let context: LoafAnalyzeContext?
            if let bake = currentBake {
                context = LoafComparisonEngine.makeAnalyzeContext(
                    currentBake: bake,
                    previous: previousRef,
                    previousAnalysis: previousAnalysis
                )
            } else {
                context = nil
            }

            isAnalyzing = true
            progressMessage = "Analyzing loaf..."
            analytics.track(.analysisStarted)
            let result = try await repository.analyzeLoaf(
                imagePath: imagePath,
                promptVersion: "v1",
                context: context
            )
            latestResult = result
            isAnalyzing = false
            analytics.track(.analysisCompleted)

            if let bakeID, let bake = currentBake {
                isPersisting = true
                progressMessage = "Saving analysis..."
                let snapshot = LoafComparisonEngine.buildSnapshot(
                    currentBake: bake,
                    currentAnalysis: result.analysis,
                    previous: previousRef,
                    previousAnalysis: previousAnalysis,
                    recommendation: result.analysis.recommendation
                )
                let persistResult = LoafAnalyzeResult(
                    model: result.model,
                    promptVersion: result.promptVersion,
                    analysis: result.analysis.encodingWithComparison(snapshot)
                )
                latestPersistedIDs = try await repository.persistLoafAnalysis(
                    bakeID: bakeID,
                    imagePath: imagePath,
                    result: persistResult,
                    qualityScore: nil,
                    qualityIssue: nil
                )
                bakeAnalyses = try await repository.fetchLoafAnalyses(forBakeID: bakeID)
                let reloaded = bakeAnalyses.sorted { $0.createdAt > $1.createdAt }.first
                if let saved = reloaded?.analysis.comparison {
                    comparison = LoafComparisonEngine.presentation(
                        from: saved,
                        analysis: reloaded?.analysis ?? persistResult.analysis,
                        previousBakeName: previousRef?.bake.name
                    )
                    latestResult = LoafAnalyzeResult(
                        model: reloaded?.model ?? persistResult.model,
                        promptVersion: reloaded?.promptVersion ?? persistResult.promptVersion,
                        analysis: reloaded?.analysis ?? persistResult.analysis
                    )
                } else {
                    comparison = LoafComparisonEngine.presentation(
                        from: snapshot,
                        analysis: persistResult.analysis,
                        previousBakeName: previousRef?.bake.name
                    )
                    latestResult = persistResult
                }
                isPersisting = false
            }

            progressMessage = nil
            errorMessage = nil
        } catch let appError as AppError {
            isUploading = false
            isAnalyzing = false
            isPersisting = false
            progressMessage = nil
            errorMessage = appError.errorDescription
            analytics.track(.analysisFailed)
        } catch {
            isUploading = false
            isAnalyzing = false
            isPersisting = false
            progressMessage = nil
            errorMessage = AppError.analysisFailed.errorDescription
            analytics.track(.analysisFailed)
        }
    }

    func saveAsBaseline() {
        didSaveBaseline = true
    }

    func loadHistory() async {
        do {
            history = try await repository.fetchHistory()
            if let bakeID {
                bakeAnalyses = try await repository.fetchLoafAnalyses(forBakeID: bakeID)
            }
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
