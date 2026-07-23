import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var billingManager: BillingManager

    var body: some View {
        NavigationStack {
            Group {
                switch billingManager.state {
                case .loading:
                    ProgressView("Loading plans...")
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
                    ContentUnavailableView(
                        "Subscriptions unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Baking App Pro")
            .task {
                environment.analytics.track(.paywallViewed)
                await billingManager.loadOfferings()
            }
        }
    }
}

