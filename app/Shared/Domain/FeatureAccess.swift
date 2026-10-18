enum ProductFeature: Hashable, Sendable {
    case variableReplacement
}

enum FeatureAvailability: Equatable, Sendable {
    case included
    case requiresPro
    case unavailable

    var isAvailable: Bool {
        switch self {
        case .included: true
        case .requiresPro, .unavailable: false
        }
    }
}

struct FeaturePolicy: Sendable {
    let proFeatures: Set<ProductFeature>
    let subscriptionsOffered: Bool

    func availability(_ feature: ProductFeature, pro: Bool) -> FeatureAvailability {
        switch (proFeatures.contains(feature), pro, subscriptionsOffered) {
        case (false, _, _), (_, true, _): .included
        case (true, false, true): .requiresPro
        case (true, false, false): .unavailable
        }
    }
}

enum FeatureAccess {
    static let policy = FeaturePolicy(proFeatures: [], subscriptionsOffered: false)
    static var subscriptionsOffered: Bool { policy.subscriptionsOffered }

    static func availability(_ feature: ProductFeature, pro: Bool) -> FeatureAvailability {
        policy.availability(feature, pro: pro)
    }
}
