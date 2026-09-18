import SwiftUI
import UIKit

/// Product-owned text and color traits are stable across accessibility settings.
struct NibbleInterface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(.large)
            .environment(\.legibilityWeight, .regular)
    }

    static func apply(to traits: inout UITraitOverrides) {
        traits.preferredContentSizeCategory = .large
        traits.legibilityWeight = .regular
        traits.accessibilityContrast = .normal
    }
}
