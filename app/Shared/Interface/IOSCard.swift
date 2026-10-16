import AppMacros
import SwiftUI

/// A token-styled surface for related content. Explicit child foreground styles remain in control.
@Equatable
public struct IOSCard<Content: View>: View {
    private let inputRevision = UUID()
    @Environment(\.iosDesignTokens) private var tokens
    @Environment(\.colorScheme) private var scheme
    @SkipEquatable private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .foregroundStyle(tokens.palette(for: scheme).cardForeground)
            .padding(tokens.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.palette(for: scheme).card, in: RoundedRectangle(cornerRadius: tokens.radii.card))
            .overlay {
                RoundedRectangle(cornerRadius: tokens.radii.card)
                    .strokeBorder(tokens.palette(for: scheme).border, lineWidth: tokens.controls.borderWidth)
            }
    }
}
