import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class StarterWorkflowViewModel: ObservableObject {
    @Published var starters: [Starter] = []
    @Published var feedingLogs: [FeedingLog] = []
    @Published var timeline: [StarterTimelineItem] = []
    @Published var starterState: StarterState?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var validatedImage: StarterValidatedImage?
    @Published var pendingImagePath: String?
    @Published var pendingAIResponse: StarterAIResponse?
    @Published var persistedIDs: PersistedStarterAnalysisIDs?
    @Published var recommendation: Recommendation?

    private let repository: StarterRepository
    private let analytics: AnalyticsTracking
    private let imageValidator: StarterImageValidator
    private let isProUser: Bool

    private var didTrackFirstUpload = false
    private var didTrackFirstRecommendationView = false
    private var didTrackFirstOutcome = false
    private var lastAnalyzeDate: Date?
    private var pendingAnalyzeResult: StarterAnalyzeResult?

    init(
        repository: StarterRepository,
        analytics: AnalyticsTracking,
        imageValidator: StarterImageValidator = StarterImageValidator(),
        isProUser: Bool
    ) {
        self.repository = repository
        self.analytics = analytics
        self.imageValidator = imageValidator
        self.isProUser = isProUser
    }

    var activeStarter: Starter? {
        starters.first(where: { $0.active }) ?? starters.first
    }

    func loadStarters() async {
        isLoading = true
        defer { isLoading = false }
        do {
            starters = try await repository.listStarters()
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async -> Bool {
        do {
            let starter = try await repository.createStarter(name: name, hydrationPreference: hydrationPreference, active: active)
            starters.insert(starter, at: 0)
            analytics.track(.starterCreated)
            return true
        } catch {
            errorMessage = userMessage(error)
            return false
        }
    }

    func setActiveStarter(starterID: UUID) async {
        do {
            try await repository.setActiveStarter(starterID: starterID)
            await loadStarters()
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func loadFeedingHistory(starterID: UUID) async {
        do {
            feedingLogs = try await repository.listFeedingLogs(starterID: starterID)
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func createFeedingLog(
        starterID: UUID,
        loggedAt: Date,
        roomTempC: Double,
        flourG: Int?,
        waterG: Int?,
        starterG: Int?,
        notes: String?
    ) async -> Bool {
        do {
            _ = try await repository.createFeedingLog(
                starterID: starterID,
                loggedAt: loggedAt,
                roomTempC: roomTempC,
                flourG: flourG,
                waterG: waterG,
                starterG: starterG,
                notes: notes
            )
            analytics.track(.feedingLogged)
            await loadFeedingHistory(starterID: starterID)
            return true
        } catch {
            errorMessage = userMessage(error)
            return false
        }
    }

    func loadStarterState(starterID: UUID) async {
        do {
            starterState = try await repository.fetchStarterState(starterID: starterID)
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func loadTimeline(starterID: UUID) async {
        do {
            timeline = try await repository.listTimeline(starterID: starterID)
            recommendation = timeline.first?.recommendation
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func refreshHomeContext() async {
        isLoading = true
        defer { isLoading = false }

        let previousActiveStarterID = activeStarter?.id
        let previousStarters = starters

        do {
            starters = try await repository.listStarters()
        } catch {
            starters = previousStarters
            errorMessage = userMessage(error)
            return
        }

        guard let latestActiveStarter = activeStarter else {
            starterState = nil
            feedingLogs = []
            timeline = []
            recommendation = nil
            return
        }

        if previousActiveStarterID != latestActiveStarter.id {
            starterState = nil
            feedingLogs = []
            timeline = []
            recommendation = nil
        }

        do {
            starterState = try await repository.fetchStarterState(starterID: latestActiveStarter.id)
        } catch {
            errorMessage = userMessage(error)
        }

        do {
            feedingLogs = try await repository.listFeedingLogs(starterID: latestActiveStarter.id)
        } catch {
            errorMessage = userMessage(error)
        }

        do {
            timeline = try await repository.listTimeline(starterID: latestActiveStarter.id)
            recommendation = timeline.first?.recommendation
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func handleSelectedPhoto() async {
        guard let selectedItem else { return }
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self) else {
                throw AppError.imageValidationFailed("Could not load selected image.")
            }
            let validated = try imageValidator.validate(data: data)
            validatedImage = validated
            selectedImage = UIImage(data: validated.jpegData)
            errorMessage = nil
        } catch {
            pendingAIResponse = nil
            pendingAnalyzeResult = nil
            persistedIDs = nil
            errorMessage = userMessage(error)
        }
    }

    func analyzeStarter(starterID: UUID, userID: UUID) async {
        guard isProUser else {
            errorMessage = AppError.subscriptionRequired.localizedDescription
            return
        }
        guard let validatedImage else {
            errorMessage = "Select a valid image first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let path = try await repository.uploadStarterImage(
                data: validatedImage.jpegData,
                userID: userID,
                starterID: starterID,
                date: Date()
            )
            if !didTrackFirstUpload {
                analytics.track(.firstScanUploaded)
                didTrackFirstUpload = true
            } else if let lastAnalyzeDate, Calendar.current.dateComponents([.day], from: lastAnalyzeDate, to: Date()).day ?? 99 <= 7 {
                analytics.track(.scanRepeatedWithin7d)
            }
            lastAnalyzeDate = Date()
            pendingImagePath = path
            let analyzeResult = try await repository.analyzeStarter(starterID: starterID, imagePath: path, promptVersion: "v1")
            pendingAnalyzeResult = analyzeResult
            pendingAIResponse = analyzeResult.analysis
            persistedIDs = nil
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func savePendingAnalysis(starterID: UUID) async {
        guard
            let pendingAnalyzeResult,
            let pendingImagePath
        else {
            errorMessage = "No analysis result available to save."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = try await repository.persistStarterAnalysis(
                starterID: starterID,
                imagePath: pendingImagePath,
                qualityScore: validatedImage?.qualityScore,
                qualityIssue: validatedImage?.qualityIssue,
                model: pendingAnalyzeResult.model,
                promptVersion: pendingAnalyzeResult.promptVersion,
                response: pendingAnalyzeResult.analysis
            )
            persistedIDs = ids
            await loadStarterState(starterID: starterID)
            await loadTimeline(starterID: starterID)
            if !didTrackFirstRecommendationView {
                analytics.track(.firstAIRecommendationViewed)
                didTrackFirstRecommendationView = true
            }
        } catch {
            errorMessage = userMessage(error)
        }
    }

    func markRecommendationOutcome(_ outcome: RecommendationOutcome) async {
        guard let recommendation else { return }
        do {
            let updated = try await repository.updateRecommendationOutcome(recommendationID: recommendation.id, outcome: outcome)
            self.recommendation = updated
            if !didTrackFirstOutcome {
                analytics.track(.firstRecommendationMarkedOutcome)
                didTrackFirstOutcome = true
            }
        } catch {
            errorMessage = userMessage(error)
        }
    }

    private func userMessage(_ error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        }
        return AppError.unknown("Something went wrong. Please try again.").localizedDescription
    }
}

