import SwiftUI

struct AnalysisResultView: View {
    let result: LoafAnalyzeResult
    let imagePath: String?
    @ObservedObject var viewModel: AnalysisViewModel

    @State private var signedURL: URL?

    private var analysis: LoafAIAnalysis { result.analysis }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let signedURL {
                    AsyncImage(url: signedURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                scoreRow("Overall", analysis.overallScore)
                scoreRow("Crumb", analysis.crumbScore)
                scoreRow("Crust", analysis.crustScore)
                scoreRow("Oven Spring", analysis.ovenSpringScore)

                labeledList("Strengths", analysis.strengths)
                labeledList("Improvements", analysis.improvements)
                labeledList("Next Steps", analysis.nextSteps)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary").font(.headline)
                    Text(analysis.summary)
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .task {
            if let imagePath {
                signedURL = await viewModel.signedImageURL(path: imagePath)
            }
        }
    }

    private func scoreRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(String(value))
        }
    }

    private func labeledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                }
            }
        }
    }
}
