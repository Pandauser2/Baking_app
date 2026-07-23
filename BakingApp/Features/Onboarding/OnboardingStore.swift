import Foundation

@MainActor
final class OnboardingStore: ObservableObject {
    @Published private(set) var isCompleted: Bool

    private let defaults: UserDefaults
    private let key = "onboarding.completed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isCompleted = defaults.bool(forKey: key)
    }

    func complete() {
        defaults.set(true, forKey: key)
        isCompleted = true
    }
}

