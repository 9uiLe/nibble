import AppMacros
import SwiftUI

@Equatable
struct LibraryLoadingRow: @MainActor EquatableBodyView {
    let title: String

    var equatableBody: some View {
        ProgressView {
            Text(title)
                .font(.nibbleBody)
        }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("library.loading")
    }
}
