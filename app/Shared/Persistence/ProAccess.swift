import Foundation

/// The containing app writes only expiration dates from verified StoreKit transactions.
enum ProEntitlement: Equatable {
    case unavailable
    case absent
    case active(until: Date)
    case expired(at: Date)
    case invalid

    init(stored value: Any?, now: Date) {
        guard let value else {
            self = .absent
            return
        }
        guard let expiration = value as? Date, expiration.timeIntervalSince1970.isFinite else {
            self = .invalid
            return
        }
        self = expiration > now ? .active(until: expiration) : .expired(at: expiration)
    }

    var isActive: Bool {
        switch self {
        case .active: true
        case .unavailable, .absent, .expired, .invalid: false
        }
    }
}

/// App Group storage is an extension-readable snapshot, never a source of StoreKit verification.
enum ProAccess {
    private static let group = "group.nibble.9uiLe.com"
    private static let expirationKey = "pro.entitlementExpiration"

    static func entitlement(now: Date = Date()) -> ProEntitlement {
        guard let defaults = UserDefaults(suiteName: group) else { return .unavailable }
        return ProEntitlement(stored: defaults.object(forKey: expirationKey), now: now)
    }

    static func isActive() -> Bool { entitlement().isActive }

    static func update(expiration: Date?) {
        let defaults = UserDefaults(suiteName: group)
        if let expiration { defaults?.set(expiration, forKey: expirationKey) }
        else { defaults?.removeObject(forKey: expirationKey) }
    }
}
