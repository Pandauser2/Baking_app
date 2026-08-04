import XCTest
@testable import BakingApp

@MainActor
final class BakeJournalViewModelTests: XCTestCase {
    func testRefreshEmptyState() async {
        let bakeRepo = FakeBakeRepository(bakes: [])
        let starterRepo = FakeBakeStarterRepository(starters: [Self.starter])
        let viewModel = BakeJournalViewModel(bakeRepository: bakeRepo, starterRepository: starterRepo)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.loadState, .empty)
        XCTAssertTrue(viewModel.bakes.isEmpty)
    }

    func testCreateBakeInsertsAndSelects() async {
        let bakeRepo = FakeBakeRepository(bakes: [])
        let starterRepo = FakeBakeStarterRepository(starters: [Self.starter])
        let viewModel = BakeJournalViewModel(bakeRepository: bakeRepo, starterRepository: starterRepo)

        let created = await viewModel.createBake(Self.validInput(starterID: Self.starter.id))

        XCTAssertNotNil(created)
        XCTAssertEqual(viewModel.bakes.count, 1)
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.selectedBake?.id, created?.id)
    }

    func testCreateBakeSurfacesValidationError() async {
        let bakeRepo = FakeBakeRepository(bakes: [])
        let starterRepo = FakeBakeStarterRepository(starters: [Self.starter])
        let viewModel = BakeJournalViewModel(bakeRepository: bakeRepo, starterRepository: starterRepo)
        var input = Self.validInput(starterID: Self.starter.id)
        input.name = ""

        let created = await viewModel.createBake(input)

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.errorMessage, BakeValidationError.blankName.errorDescription)
        XCTAssertEqual(bakeRepo.createCallCount, 0)
    }

    func testSelectBakeFetchesDetails() async {
        let existing = Self.makeBake(name: "Cached")
        let bakeRepo = FakeBakeRepository(bakes: [existing])
        bakeRepo.fetchOverride = Self.makeBake(id: existing.id, name: "Fetched")
        let viewModel = BakeJournalViewModel(
            bakeRepository: bakeRepo,
            starterRepository: FakeBakeStarterRepository(starters: [Self.starter])
        )

        await viewModel.selectBake(id: existing.id)

        XCTAssertEqual(viewModel.selectedBake?.name, "Fetched")
        XCTAssertEqual(bakeRepo.fetchCallCount, 1)
    }

    private static let starter = Starter(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Test Starter",
        hydrationPreference: 100,
        createdAt: Date(timeIntervalSince1970: 1),
        active: true
    )

    private static func validInput(starterID: UUID) -> BakeCreateInput {
        BakeCreateInput(
            starterID: starterID,
            bakedAt: Date(),
            name: "VM Bake",
            doughHydrationPercent: 75,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            mixingMethod: BakeMixingMethod.hand.rawValue,
            shapingMethod: BakeShapingMethod.boule.rawValue,
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40,
            resultRating: 4,
            fermentationTemperatureCelsius: nil,
            fermentationTemperatureSource: nil,
            retardationMinutes: nil,
            numberOfFolds: nil,
            steamingMethod: nil,
            flourNotes: nil,
            notes: nil
        )
    }

    private static func makeBake(id: UUID = UUID(), name: String) -> Bake {
        Bake(
            id: id,
            userID: starter.userID,
            starterID: starter.id,
            bakedAt: Date(),
            name: name,
            doughHydrationPercent: 75,
            bulkFermentationMinutes: 240,
            finalProofMinutes: 120,
            mixingMethod: "Hand mix",
            shapingMethod: "Boule",
            ovenTemperatureCelsius: 230,
            bakingTimeMinutes: 40,
            resultRating: 4,
            fermentationTemperatureCelsius: nil,
            fermentationTemperatureSource: nil,
            retardationMinutes: nil,
            numberOfFolds: nil,
            steamingMethod: nil,
            flourNotes: nil,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private final class FakeBakeRepository: BakeRepository {
    var bakes: [Bake]
    var fetchOverride: Bake?
    private(set) var createCallCount = 0
    private(set) var fetchCallCount = 0

    init(bakes: [Bake]) {
        self.bakes = bakes
    }

    func listBakes() async throws -> [Bake] { bakes }

    func fetchBake(bakeID: UUID) async throws -> Bake {
        fetchCallCount += 1
        if let fetchOverride { return fetchOverride }
        guard let bake = bakes.first(where: { $0.id == bakeID }) else {
            throw AppError.unknown("missing")
        }
        return bake
    }

    func createBake(_ input: BakeCreateInput) async throws -> Bake {
        createCallCount += 1
        let validated = try BakeValidation.validate(input)
        let bake = Bake(
            id: UUID(),
            userID: UUID(),
            starterID: validated.starterID,
            bakedAt: validated.bakedAt,
            name: validated.name,
            doughHydrationPercent: validated.doughHydrationPercent,
            bulkFermentationMinutes: validated.bulkFermentationMinutes,
            finalProofMinutes: validated.finalProofMinutes,
            mixingMethod: validated.mixingMethod,
            shapingMethod: validated.shapingMethod,
            ovenTemperatureCelsius: validated.ovenTemperatureCelsius,
            bakingTimeMinutes: validated.bakingTimeMinutes,
            resultRating: validated.resultRating,
            fermentationTemperatureCelsius: validated.fermentationTemperatureCelsius,
            fermentationTemperatureSource: validated.fermentationTemperatureSource,
            retardationMinutes: validated.retardationMinutes,
            numberOfFolds: validated.numberOfFolds,
            steamingMethod: validated.steamingMethod,
            flourNotes: validated.flourNotes,
            notes: validated.notes,
            createdAt: Date(),
            updatedAt: Date()
        )
        bakes.insert(bake, at: 0)
        return bake
    }
}

private struct FakeBakeStarterRepository: StarterRepository {
    let starters: [Starter]

    func listStarters() async throws -> [Starter] { starters }
    func createStarter(name: String, hydrationPreference: Double?, active: Bool) async throws -> Starter { starters[0] }
    func setActiveStarter(starterID: UUID) async throws {}
    func fetchStarter(starterID: UUID) async throws -> Starter {
        guard let starter = starters.first(where: { $0.id == starterID }) else {
            throw AppError.unknown("missing starter")
        }
        return starter
    }
    func fetchStarterState(starterID: UUID) async throws -> StarterState? { nil }
    func createFeedingLog(starterID: UUID, loggedAt: Date, roomTempC: Double, flourG: Int?, waterG: Int?, starterG: Int?, notes: String?) async throws -> FeedingLog {
        throw AppError.unknown("unused")
    }
    func listFeedingLogs(starterID: UUID) async throws -> [FeedingLog] { [] }
    func uploadStarterImage(data: Data, userID: UUID, starterID: UUID, date: Date) async throws -> String { "" }
    func analyzeStarter(starterID: UUID, imagePath: String, promptVersion: String) async throws -> StarterAnalyzeResult {
        throw AppError.unknown("unused")
    }
    func persistStarterAnalysis(starterID: UUID, imagePath: String, qualityScore: Double?, qualityIssue: String?, model: String, promptVersion: String, response: StarterAIResponse) async throws -> PersistedStarterAnalysisIDs {
        throw AppError.unknown("unused")
    }
    func fetchRecommendation(recommendationID: UUID) async throws -> Recommendation {
        throw AppError.unknown("unused")
    }
    func listTimeline(starterID: UUID) async throws -> [StarterTimelineItem] { [] }
    func updateRecommendationOutcome(recommendationID: UUID, outcome: RecommendationOutcome) async throws -> Recommendation {
        throw AppError.unknown("unused")
    }
    func signedImageURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        URL(string: "https://example.com")!
    }
}
