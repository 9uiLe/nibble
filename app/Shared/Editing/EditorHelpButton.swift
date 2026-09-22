import AppMacros
import SwiftUI

@Equatable
struct EditorHelpButton: View {
    private let inputRevision = UUID()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("入力と保存について")
                .font(.nibbleBody)
                .frame(minHeight: InterfaceMetrics.touchSize)
                .contentShape(.rect)
        }
    }
}
