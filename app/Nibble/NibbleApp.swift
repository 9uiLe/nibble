import SwiftUI
import StoreKit
import Observation

@MainActor @Observable
final class ProSubscription {
    static let productIDs = ["nibble.pro.subscription.monthly", "nibble.pro.subscription.yearly"]
    private(set) var isActive = ProAccess.isActive()
    private(set) var checked = false

    func refresh() async {
        var expiration: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil,
                  let date = transaction.expirationDate else { continue }
            // StoreKit also yields subscriptions in billing grace. Share can use a
            // bounded snapshot until the containing app refreshes again.
            let validUntil = max(date, Date().addingTimeInterval(date <= Date() ? 86_400 : 0))
            if validUntil > (expiration ?? .distantPast) { expiration = validUntil }
        }
        ProAccess.update(expiration: expiration)
        isActive = ProAccess.isActive()
        checked = true
    }

    func watchUpdates() async {
        for await result in StoreKit.Transaction.updates {
            if case .verified(let transaction) = result {
                await refresh()
                await transaction.finish()
            }
        }
    }
}

@main
struct NibbleApp: App {
    private let store = SnippetStore(location: SnippetLocation.database)

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store, effects: SystemLibraryEffects())
                .modifier(NibbleInterface())
                .background(SceneInterfaceDefaults())
        }
    }
}
