import SwiftUI

struct RecommendationCardView: View {
    let recommendation: Recommendation
    let onSelect: (RecommendationOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Step")
                .font(.headline)
            Text(recommendation.recommendation)
            if let dueAt = recommendation.dueAt {
                Text("Due: \(dueAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Outcome: \(recommendation.outcome.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.caption)

            HStack {
                ForEach([RecommendationOutcome.followed, .helpful, .notHelpful, .skipped], id: \.rawValue) { outcome in
                    Button(outcomeButtonText(outcome)) {
                        onSelect(outcome)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func outcomeButtonText(_ outcome: RecommendationOutcome) -> String {
        switch outcome {
        case .followed: return "Followed"
        case .helpful: return "Helpful"
        case .notHelpful: return "Not Helpful"
        case .skipped: return "Skipped"
        case .unknown: return "Unknown"
        }
    }
}

