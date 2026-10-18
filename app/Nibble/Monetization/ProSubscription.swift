import Foundation
import Observation
import StoreKit

@MainActor @Observable
final class ProSubscription {
    static let productIDs = ["nibble.pro.subscription.monthly", "nibble.pro.subscription.yearly"]
    private(set) var isActive = ProAccess.isActive()
    private(set) var checked = false
    private var request: UUID?
    private let readExpiration: @MainActor () async -> Date?
    private let updateAccess: @MainActor (Date?) -> Bool
    init(readExpiration: @escaping @MainActor () async -> Date? = { await ProSubscription.currentExpiration() },
         updateAccess: @escaping @MainActor (Date?) -> Bool = { ProAccess.update(expiration: $0); return ProAccess.isActive() }) {
        self.readExpiration = readExpiration; self.updateAccess = updateAccess
    }
    func refresh() async {
        let token = UUID()
        request = token
        let expiration = await readExpiration()
        guard request == token, !Task.isCancelled else { return }
        isActive = updateAccess(expiration)
        checked = true
    }
    private static func currentExpiration() async -> Date? {
        var latest: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard !Task.isCancelled else { return nil }
            guard case .verified(let transaction) = result, productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, let expiry = transaction.expirationDate else { continue }
            let validThrough = expiry > Date() ? expiry : Date().addingTimeInterval(86_400)
            latest = max(latest ?? .distantPast, validThrough)
        }
        return latest
    }
    func watchUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard !Task.isCancelled else { return }
            guard case .verified(let transaction) = result else { continue }
            await refresh()
            await transaction.finish()
        }
    }
}
