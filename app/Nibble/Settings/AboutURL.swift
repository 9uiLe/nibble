import AppMacros
import SwiftUI

@Equatable
struct AboutURL: @MainActor EquatableBodyView {
    let title: LocalizedStringKey
    let value: String

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.nibbleBody)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
