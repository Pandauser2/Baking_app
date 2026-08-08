import SwiftUI

/// Observes the loaf analysis view model so historical reload (prepareBakeContext)
/// can leave the loading state and show the persisted snapshot.
struct LoafAnalysisResultHost: View {
    @ObservedObject var viewModel: AnalysisViewModel
    var onSaveBaseline: (() -> Void)?

    var body: some View {
        Group {
            if let result = viewModel.latestResult {
                AnalysisResultView(
                    result: result,
                    imagePath: viewModel.latestImagePath,
                    viewModel: viewModel,
                    onSaveBaseline: onSaveBaseline
                )
            } else {
                ProgressView("Loading analysis...")
                    .task { await viewModel.prepareBakeContext() }
            }
        }
    }
}
