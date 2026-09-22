import AppMacros
import SwiftUI

/// Shared item identity; density and pin placement differ by reading context.
@Equatable
struct SnippetHeading: @MainActor EquatableBodyView {
    enum Style: Equatable { case library, keyboard }
    let title: String
    let pinned: Bool
    let style: Style

    var equatableBody: some View {
        HStack(alignment: style == .library ? .firstTextBaseline : .center, spacing: style == .library ? 4 : 5) {
            if style == .library && pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.nibbleAccent)
            }
            Text(title)
                .font(style == .library ? .nibbleTitle : .subheadline.weight(.medium))
                .foregroundStyle(.primary).lineLimit(style == .library ? 2 : 1)
            if style == .keyboard && pinned {
                Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
