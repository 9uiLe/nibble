import Foundation

enum ProEntitlement: Equatable {
    case unavailable
    case absent
    case active(until: Date)
    case expired(at: Date)
    case invalid

    init(stored value: Any?, now: Date) {
        switch value {
        case nil: self = .absent
        case let expiration as Date:
            guard expiration.timeIntervalSince1970.isFinite else {
                self = .invalid
                return
            }
            self = now < expiration ? .active(until: expiration) : .expired(at: expiration)
        default: self = .invalid
        }
    }

    var isActive: Bool {
        guard case .active = self else { return false }
        return true
    }
}

/// This snapshot crosses the process boundary; StoreKit verification remains in
/// the containing app and cannot be inferred from a stored expiration alone.
enum ProAccess {
    private static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: "group.nibble.9uiLe.com") }
    private static let key = "pro.entitlementExpiration"

    static func entitlement(now: Date = Date()) -> ProEntitlement {
        guard let sharedDefaults else { return .unavailable }
        return ProEntitlement(stored: sharedDefaults.object(forKey: key), now: now)
    }

    static func isActive() -> Bool { entitlement().isActive }

    static func update(expiration: Date?) {
        guard let defaults = sharedDefaults else { return }
        switch expiration {
        case .some(let expiration): defaults.set(expiration, forKey: key)
        case .none: defaults.removeObject(forKey: key)
        }
    }
}
