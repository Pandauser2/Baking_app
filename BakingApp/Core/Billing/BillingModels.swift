import Foundation

enum BillingState: Equatable {
    case loading
    case ready
    case purchaseSuccess
    case cancelled
    case failure(String)
}

struct SubscriptionOffer: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
}

