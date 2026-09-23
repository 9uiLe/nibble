import AppMacros
import SwiftUI

@Equatable
struct KeyboardStatusMessage: @MainActor EquatableBodyView {
    let notice: KeyboardModel.Notice

    var equatableBody: some View {
        Text(notice.message)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("keyboard.status")
    }
}
