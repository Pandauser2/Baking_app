import SwiftUI

struct AnalysisHistoryView: View {
    @ObservedObject var viewModel: AnalysisViewModel

    var body: some View {
        List(viewModel.history) { scan in
            AnalysisHistoryRow(scan: scan, viewModel: viewModel)
        }
        .overlay(viewModel.history.isEmpty ? AnyView(
            VStack(spacing: 10) {
                Image(systemName: "photo")
                Text("No analyses yet")
            }.foregroundStyle(.secondary)
        ) : AnyView(EmptyView()))
        .navigationTitle("History")
        .task {
            await viewModel.loadHistory()
        }
    }
}

private struct AnalysisHistoryRow: View {
    let scan: LoafScan
    @ObservedObject var viewModel: AnalysisViewModel
    @State private var signedURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let signedURL {
                    AsyncImage(url: signedURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Overall: \(scan.overallScore ?? 0)")
                    .font(.headline)
                if let summary = scan.aiSummary {
                    Text(summary)
                        .lineLimit(2)
                }
            }
        }
        .task {
            signedURL = await viewModel.signedImageURL(path: scan.imagePath)
        }
    }
}

