enum ProductFeature: Hashable, Sendable {
    case variableReplacement
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

/// The app and its extensions use the same feature audience and verified Pro grant.
enum FeatureAccess {
    static let policy = FeaturePolicy(proFeatures: [], subscriptionsOffered: false)
    static var subscriptionsOffered: Bool { policy.subscriptionsOffered }

    static func availability(_ feature: ProductFeature, pro: Bool) -> FeatureAvailability {
        policy.availability(feature, pro: pro)
    }
}
