import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var billingManager: BillingManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch billingManager.state {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView("Loading plans...")
                        Text("Preparing your subscription options.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .ready, .purchaseSuccess, .cancelled:
                    List {
                        Section("Subscription") {
                            ForEach(billingManager.offers) { offer in
                                Button {
                                    Task {
                                        await billingManager.purchase(productID: offer.id)
                                        if case .purchaseSuccess = billingManager.state {
                                            environment.analytics.track(.purchaseCompleted)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(offer.title)
                                        Spacer()
                                        Text(offer.price)
                                    }
                                }
                            }
                        }

                        Section {
                            Button("Restore Purchases") {
                                Task {
                                    await billingManager.restorePurchases()
                                    environment.analytics.track(.purchaseRestored)
                                }
                            }
                        }

                        if let bannerMessage = billingManager.bannerMessage {
                            Section("Status") {
                                Text(bannerMessage)
                            }
                        }
                    }
                case .failure(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text("Subscriptions unavailable")
                            .font(.headline)
                        Text(PaywallPresentationRules.failureMessage(message))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await billingManager.loadOfferings() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Baking App Pro")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier(PaywallPresentationRules.closeButtonAccessibilityIdentifier)
                }
            }
            .task {
                environment.analytics.track(.paywallViewed)
                await billingManager.loadOfferings()
            }
        }
    }
}

enum PaywallPresentationRules {
    static let closeButtonAccessibilityIdentifier = "paywall-close-button"

    static func showsRetry(for state: BillingState) -> Bool {
        if case .failure = state {
            return true
        }
        return false
    }

    static func canDismiss(for state: BillingState) -> Bool {
        switch state {
        case .loading, .ready, .purchaseSuccess, .cancelled, .failure:
            return true
        }
    }

    static func failureMessage(_: String) -> String {
        return "We couldn't load subscriptions right now. Please try again."
    }
}

