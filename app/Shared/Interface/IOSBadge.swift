import AppMacros
import SwiftUI

public enum IOSBadgeVariant: CaseIterable, Equatable {
    case neutral, secondary, success, destructive
}

@Equatable
public struct IOSBadge: View {
    private let inputRevision = UUID()
    @Environment(\.iosDesignTokens) private var tokens
    @Environment(\.colorScheme) private var scheme
    public let title: String
    public let symbol: String?
    public let variant: IOSBadgeVariant

    public init(_ title: String, symbol: String? = nil, variant: IOSBadgeVariant = .neutral) {
        self.title = title
        self.symbol = symbol
        self.variant = variant
    }

    public var body: some View {
        let colors = tokens.palette(for: scheme)
        HStack(spacing: tokens.spacing.xxs) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            Text(title)
        }
        .font(tokens.typography.badge)
        .foregroundStyle(foreground(colors))
        .padding(.horizontal, tokens.spacing.xs)
        .padding(.vertical, tokens.spacing.xxs)
        .background(background(colors), in: RoundedRectangle(cornerRadius: tokens.radii.badge))
    }

    private func foreground(_ colors: IOSColorTokens) -> Color {
        switch variant {
        case .neutral: colors.primaryForeground
        case .secondary: colors.secondaryForeground
        case .success: colors.successForeground
        case .destructive: colors.destructiveForeground
        }
    }

    private func background(_ colors: IOSColorTokens) -> Color {
        switch variant {
        case .neutral: colors.primary
        case .secondary: colors.secondary
        case .success: colors.success
        case .destructive: colors.destructive
        }
    }
}
