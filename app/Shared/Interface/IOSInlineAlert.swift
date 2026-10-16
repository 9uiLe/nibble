import AppMacros
import SwiftUI

enum IOSAlertVariant: Equatable {
    case information, error
}

@Equatable
struct IOSInlineAlert: View {
    private let inputRevision = UUID()
    @Environment(\.iosDesignTokens) private var tokens
    @Environment(\.colorScheme) private var scheme
    let title: String
    let message: String
    let variant: IOSAlertVariant

    init(_ title: String, message: String, variant: IOSAlertVariant = .information) {
        self.title = title
        self.message = message
        self.variant = variant
    }

    var body: some View {
        let colors = tokens.palette(for: scheme)
        HStack(alignment: .top, spacing: tokens.spacing.sm) {
            Image(systemName: variant == .error ? "exclamationmark.triangle" : "info.circle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: tokens.spacing.xxs) {
                Text(title).font(tokens.typography.alertTitle)
                Text(message).font(tokens.typography.alertMessage)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(variant == .error ? colors.destructiveText : colors.foreground)
        .padding(tokens.spacing.md)
        .background(colors.muted, in: RoundedRectangle(cornerRadius: tokens.radii.control))
    }
}
