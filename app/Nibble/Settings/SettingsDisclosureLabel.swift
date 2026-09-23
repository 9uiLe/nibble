import AppMacros
import SwiftUI

/// A sheet destination uses the same disclosure cue as a pushed destination.
@Equatable
struct SettingsDisclosureLabel: @MainActor EquatableBodyView {
    let title: String
    let detail: String
    let systemImage: String
    let showsChevron: Bool

    var equatableBody: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundStyle(Color.nibbleAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.nibbleTitle).foregroundStyle(.primary)
                Text(detail).font(.nibbleBody).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
    }
}
