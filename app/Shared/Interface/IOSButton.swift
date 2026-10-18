import SwiftUI

enum IOSButtonVariant: Equatable {
    case primary, secondary, destructive
}

enum IOSButtonSize: Equatable {
    case compact, regular

    func horizontalPadding(_ spacing: IOSSpacingTokens) -> CGFloat {
        switch self {
        case .compact: spacing.sm
        case .regular: spacing.md
        }
    }

    func minimumHeight(_ controls: IOSControlTokens) -> CGFloat {
        switch self {
        case .compact: controls.minimumHeight - 4
        case .regular: controls.minimumHeight
        }
    }
}

/// A reusable style for native Button, including Button(role: .destructive).
struct IOSButtonStyle: ButtonStyle {
    @Environment(\.iosDesignTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    var variant: IOSButtonVariant
    var size: IOSButtonSize

    init(_ variant: IOSButtonVariant = .primary, size: IOSButtonSize = .regular) {
        self.variant = variant
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        let colors = tokens.colors
        let effective = configuration.role == .destructive ? IOSButtonVariant.destructive : variant
        configuration.label
            .font(tokens.typography.button)
            .foregroundStyle(isEnabled ? foreground(effective, colors: colors) : colors.mutedForeground)
            .padding(.vertical, tokens.spacing.xs)
            .frame(maxWidth: .infinity, minHeight: size.minimumHeight(tokens.controls))
            .padding(.horizontal, size.horizontalPadding(tokens.spacing))
            .background(isEnabled ? background(effective, colors: colors) : colors.muted, in: RoundedRectangle(cornerRadius: tokens.radii.control))
            .overlay {
                RoundedRectangle(cornerRadius: tokens.radii.control)
                    .strokeBorder(
                        effective == .secondary || !isEnabled ? colors.border : .clear,
                        lineWidth: contrast == .increased ? tokens.controls.emphasizedBorderWidth : tokens.controls.borderWidth
                    )
            }
            .opacity(configuration.isPressed ? tokens.controls.pressedOpacity : 1)
            .contentShape(Rectangle())
    }

    private func foreground(_ variant: IOSButtonVariant, colors: IOSColorTokens) -> Color {
        switch variant {
        case .primary: colors.primaryForeground
        case .secondary: colors.secondaryForeground
        case .destructive: colors.destructiveForeground
        }
    }

    private func background(_ variant: IOSButtonVariant, colors: IOSColorTokens) -> Color {
        switch variant {
        case .primary: colors.primary
        case .secondary: colors.secondary
        case .destructive: colors.destructive
        }
    }
}
