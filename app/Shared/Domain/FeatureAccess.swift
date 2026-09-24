import Foundation

enum ProductFeature: Hashable, Sendable {
    case variableReplacement, adFree
}

enum FeatureAvailability: Equatable, Sendable {
    case included, requiresPro, unavailable

    var isAvailable: Bool { self == .included }
}

struct FeaturePolicy: Sendable {
    let proFeatures: Set<ProductFeature>
    let subscriptionsOffered: Bool

    func availability(_ feature: ProductFeature, pro: Bool) -> FeatureAvailability {
        if !proFeatures.contains(feature) || pro { return .included }
        return subscriptionsOffered ? .requiresPro : .unavailable
    }
}

/// The containing app refreshes this snapshot from verified StoreKit transactions.
enum ProAccess {
    private static let group = "group.nibble.9uiLe.com"
    private static let expirationKey = "pro.entitlementExpiration"

    static func isActive() -> Bool {
        guard let expiration = UserDefaults(suiteName: group)?.object(forKey: expirationKey) as? Date else { return false }
        return expiration > Date()
    }

    static func update(expiration: Date?) {
        let defaults = UserDefaults(suiteName: group)
        if let expiration { defaults?.set(expiration, forKey: expirationKey) }
        else { defaults?.removeObject(forKey: expirationKey) }
    }
}

/// The app and its extensions use the same feature audience and verified Pro grant.
enum FeatureAccess {
    static let policy = FeaturePolicy(proFeatures: [.adFree], subscriptionsOffered: false)
    static var subscriptionsOffered: Bool { policy.subscriptionsOffered }

    static func availability(_ feature: ProductFeature, pro: Bool) -> FeatureAvailability {
        policy.availability(feature, pro: pro)
    }
}
