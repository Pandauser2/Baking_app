import Foundation

@MainActor
final class BakeJournalViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var bakes: [Bake] = []
    @Published private(set) var starters: [Starter] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var selectedBake: Bake?

    private let bakeRepository: BakeRepository
    private let starterRepository: StarterRepository

    init(bakeRepository: BakeRepository, starterRepository: StarterRepository) {
        self.bakeRepository = bakeRepository
        self.starterRepository = starterRepository
    }

    var activeStarter: Starter? {
        starters.first(where: \.active) ?? starters.first
    }

    func refresh() async {
        loadState = .loading
        errorMessage = nil
        do {
            async let loadedBakes = bakeRepository.listBakes()
            async let loadedStarters = starterRepository.listStarters()
            let (bakesResult, startersResult) = try await (loadedBakes, loadedStarters)
            bakes = bakesResult
            starters = startersResult
            loadState = bakesResult.isEmpty ? .empty : .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not load bake journal."
            loadState = .failed(message)
            errorMessage = message
        }
    }

    func loadStartersIfNeeded() async {
        guard starters.isEmpty else { return }
        do {
            starters = try await starterRepository.listStarters()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load starters."
        }
    }

    @discardableResult
    func createBake(_ input: BakeCreateInput) async -> Bake? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let validated = try BakeValidation.validate(input)
            let created = try await bakeRepository.createBake(validated)
            if let index = bakes.firstIndex(where: { $0.bakedAt < created.bakedAt }) {
                bakes.insert(created, at: index)
            } else if let last = bakes.last, last.bakedAt >= created.bakedAt {
                bakes.append(created)
            } else {
                bakes.insert(created, at: 0)
            }
            bakes.sort { $0.bakedAt > $1.bakedAt }
            loadState = bakes.isEmpty ? .empty : .loaded
            selectedBake = created
            return created
        } catch let validation as BakeValidationError {
            errorMessage = validation.errorDescription
            return nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save bake."
            return nil
        }
    }

    func selectBake(id: UUID) async {
        errorMessage = nil
        if let cached = bakes.first(where: { $0.id == id }) {
            selectedBake = cached
        }
        do {
            let fetched = try await bakeRepository.fetchBake(bakeID: id)
            selectedBake = fetched
            if let index = bakes.firstIndex(where: { $0.id == id }) {
                bakes[index] = fetched
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load bake details."
        }
    }
}
