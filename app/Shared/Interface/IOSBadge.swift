import AppMacros
import SwiftUI

@Equatable
struct IOSBadge: View {
    private let inputRevision = UUID()
    @Environment(\.iosDesignTokens) private var tokens
    let title: String
    let symbol: String?

    init(_ title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        let colors = tokens.colors
        HStack(spacing: tokens.spacing.xxs) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            Text(title)
        }
        .font(tokens.typography.badge)
        .foregroundStyle(colors.primaryForeground)
        .padding(.horizontal, tokens.spacing.xs)
        .padding(.vertical, tokens.spacing.xxs)
        .background(colors.primary, in: RoundedRectangle(cornerRadius: tokens.radii.badge))
    }
}
