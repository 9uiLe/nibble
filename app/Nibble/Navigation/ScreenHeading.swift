import AppMacros
import SwiftUI

/// A stable heading above a root screen's scrollable content.
@Equatable
struct ScreenHeading: @MainActor EquatableBodyView {
    let title: String
    let subTitle: String?

    init(title: String, subTitle: String? = nil) {
        self.title = title
        self.subTitle = subTitle
    }

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.nibbleScreenTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("navigation.title")
            if let subTitle {
                Text(subTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("navigation.subtitle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 23)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}
