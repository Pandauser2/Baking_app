import SwiftUI

struct AnalysisResultView: View {
    let scan: LoafScan
    let imagePath: String?
    @ObservedObject var viewModel: AnalysisViewModel

    @State private var signedURL: URL?

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

                scoreRow("Overall", scan.overallScore)
                scoreRow("Crumb", scan.crumbScore)
                scoreRow("Crust", scan.crustScore)
                scoreRow("Oven Spring", scan.ovenSpringScore)

                labeledList("Strengths", scan.strengths)
                labeledList("Improvements", scan.improvements)
                labeledList("Next Steps", scan.nextSteps)

                if let summary = scan.aiSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary").font(.headline)
                        Text(summary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .task {
            let path = imagePath ?? scan.imagePath
            signedURL = await viewModel.signedImageURL(path: path)
        }
    }

    private func scoreRow(_ title: String, _ value: Int?) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(value.map(String.init) ?? "-")
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

