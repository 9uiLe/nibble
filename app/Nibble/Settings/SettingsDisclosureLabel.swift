import AppMacros
import SwiftUI

/// A sheet destination uses the same disclosure cue as a pushed destination.
@Equatable
struct SettingsDisclosureLabel: @MainActor EquatableBodyView {
    let title: String
    let systemImage: String

    var equatableBody: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
