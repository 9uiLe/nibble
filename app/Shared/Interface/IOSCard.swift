import AppMacros
import SwiftUI

/// A token-styled surface for related content. Explicit child foreground styles remain in control.
@Equatable
struct IOSCard<Content: View>: View {
    private let inputRevision = UUID()
    @Environment(\.iosDesignTokens) private var tokens
    @SkipEquatable private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(tokens.colors.cardForeground)
            .padding(tokens.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.colors.card, in: RoundedRectangle(cornerRadius: tokens.radii.card))
            .overlay {
                RoundedRectangle(cornerRadius: tokens.radii.card)
                    .strokeBorder(tokens.colors.border, lineWidth: tokens.controls.borderWidth)
            }
    }
}
