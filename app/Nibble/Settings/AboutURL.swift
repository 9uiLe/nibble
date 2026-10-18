import AppMacros
import SwiftUI

@Equatable
struct AboutURL: @MainActor EquatableBodyView {
    let title: String
    let value: String
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(Color.nibbleSecondary)
            Text(verbatim: value).textSelection(.enabled)
        }.accessibilityElement(children: .combine)
    }
}
