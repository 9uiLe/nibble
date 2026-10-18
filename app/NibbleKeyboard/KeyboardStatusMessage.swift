import AppMacros
import SwiftUI

@Equatable
struct KeyboardStatusMessage: @MainActor EquatableBodyView {
    let notice: KeyboardModel.Notice
    var equatableBody: some View {
        Text(notice.message).foregroundStyle(notice.insertedID == nil ? Color.primary : Color.nibbleKeyboardAccent)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("keyboard.status")
    }
}
