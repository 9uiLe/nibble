import SwiftUI
import UIKit

struct NibbleInterface: ViewModifier {
    func body(content: Content) -> some View {
        content.dynamicTypeSize(.large)
            .environment(\.legibilityWeight, .regular)
    }
    static func apply(to overrides: inout UITraitOverrides) {
        overrides.preferredContentSizeCategory = .large
        overrides.accessibilityContrast = .normal
        overrides.legibilityWeight = .regular
    }
}
