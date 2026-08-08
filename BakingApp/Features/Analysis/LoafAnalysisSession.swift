import Foundation

@MainActor
final class LoafAnalysisSession: ObservableObject {
    private var cache: [UUID: AnalysisViewModel] = [:]

    func viewModel(
        for bakeID: UUID,
        environment: AppEnvironment,
        isProUser: Bool
    ) -> AnalysisViewModel {
        if let existing = cache[bakeID] {
            existing.updateProStatus(isProUser)
            return existing
        }
        let created = AnalysisViewModel(
            repository: environment.loafAnalysisRepository,
            bakeID: bakeID,
            bakeRepository: environment.bakeRepository,
            isProUser: isProUser,
            analytics: environment.analytics
        )
        cache[bakeID] = created
        return created
    }
}
