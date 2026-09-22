import AppMacros
import SwiftUI

@Equatable
struct EditorHelpButton: View {
    private let inputRevision = UUID()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("入力と保存について")
                    .font(.nibbleBody)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: InterfaceMetrics.touchSize)
            .contentShape(.rect)
        }
    }
}
