import SwiftUI

enum IOSButtonVariant: Equatable { case primary, secondary, destructive }
enum IOSButtonSize: Equatable { case compact, regular }

struct IOSButtonStyle: ButtonStyle {
    @Environment(\.iosDesignTokens) private var theme
    @Environment(\.isEnabled) private var enabled
    let variant: IOSButtonVariant
    let size: IOSButtonSize
    init(_ variant: IOSButtonVariant = .primary, size: IOSButtonSize = .regular) {
        self.variant = variant
        self.size = size
    }
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive || variant == .destructive
        let filled = enabled && (variant == .primary || destructive)
        configuration.label
            .font(theme.typography.button)
            .foregroundStyle(filled ? theme.colors.primaryForeground : theme.colors.cardForeground)
            .padding(.horizontal, size == .regular ? 16 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: size == .regular ? 52 : 48)
            .background(filled ? (destructive ? theme.colors.destructive : theme.colors.primary) : theme.colors.secondary,
                        in: .rect(cornerRadius: theme.radii.control))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.control)
                    .strokeBorder(filled ? .clear : theme.colors.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? theme.controls.pressedOpacity : 1)
            .contentShape(.rect)
    }
}
