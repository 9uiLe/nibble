import AppMacros
import SwiftUI

/// A stable heading above a root screen's scrollable content.
@Equatable
struct ScreenHeading: @MainActor EquatableBodyView {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.nibbleScreenTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("navigation.title")
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("navigation.subtitle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
