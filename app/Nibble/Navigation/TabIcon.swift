import AppMacros
import SwiftUI

/// Vector artwork stays crisp at both bar sizes; the button owns its hit area.
@Equatable
struct TabIcon: @MainActor EquatableBodyView {
    let symbol: String
    let size: CGFloat

    var equatableBody: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .accessibilityHidden(true)
    }
}
