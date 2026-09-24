import Foundation
import Observation
import StoreKit

@MainActor @Observable
final class ProSubscription {
    static let productIDs = ["nibble.pro.subscription.monthly", "nibble.pro.subscription.yearly"]
    private(set) var isActive = ProAccess.isActive()
    private(set) var checked = false
    private var refreshID: UUID?
    private let readExpiration: @MainActor () async -> Date?
    private let updateAccess: @MainActor (Date?) -> Bool

    init(readExpiration: @escaping @MainActor () async -> Date? = { await ProSubscription.currentExpiration() },
         updateAccess: @escaping @MainActor (Date?) -> Bool = { expiration in
             ProAccess.update(expiration: expiration)
             return ProAccess.isActive()
         }) {
        self.readExpiration = readExpiration
        self.updateAccess = updateAccess
    }

    func refresh() async {
        let id = UUID()
        refreshID = id
        let expiration = await readExpiration()
        guard !Task.isCancelled, refreshID == id else { return }
        isActive = updateAccess(expiration)
        checked = true
    }

    private static func currentExpiration() async -> Date? {
        var expiration: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            if Task.isCancelled { return nil }
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil,
                  let date = transaction.expirationDate else { continue }
            // StoreKit also yields subscriptions in billing grace. Share can use a
            // bounded snapshot until the containing app refreshes again.
            let validUntil = max(date, Date().addingTimeInterval(date <= Date() ? 86_400 : 0))
            if validUntil > (expiration ?? .distantPast) { expiration = validUntil }
        }
        return expiration
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
