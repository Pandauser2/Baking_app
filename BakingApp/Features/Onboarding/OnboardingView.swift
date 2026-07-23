import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var index = 0

    private let pages: [OnboardingPage] = [
        .init(title: "Understand your starter", subtitle: "Track consistency with a clear process."),
        .init(title: "Get precise next steps", subtitle: "Follow practical guidance without guesswork."),
        .init(title: "Improve using baking history", subtitle: "Build better outcomes from each bake.")
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(pages[index].title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
            Text(pages[index].subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { dotIndex in
                    Circle()
                        .fill(dotIndex == index ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            Button(index == pages.count - 1 ? "Finish" : "Next") {
                if index < pages.count - 1 {
                    index += 1
                } else {
                    onComplete()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding()
    }
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
}

