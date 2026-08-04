import Foundation

@MainActor
final class BakeJournalViewModelHolder: ObservableObject {
    private var viewModel: BakeJournalViewModel?

    func viewModel(
        bakeRepository: BakeRepository,
        starterRepository: StarterRepository
    ) -> BakeJournalViewModel {
        if let viewModel {
            return viewModel
        }
        let created = BakeJournalViewModel(
            bakeRepository: bakeRepository,
            starterRepository: starterRepository
        )
        viewModel = created
        return created
    }
}
