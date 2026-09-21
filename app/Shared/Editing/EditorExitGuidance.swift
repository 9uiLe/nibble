import AppMacros
import SwiftUI

@Equatable
struct EditorExitGuidance: @MainActor EquatableBodyView {
    let isShared: Bool

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 8)
            Text("**保存**すると、一覧やキーボードで使えます。")
            Text("空白や改行は、そのまま保存されます。")
            if isShared {
                Text("**閉じる**と、下書きを残して共有元に戻ります。")
            } else {
                Text("**閉じる**と、編集内容が下書きに残ります。")
            }
        }
        .font(.nibbleBody).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Color.nibbleCanvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.exitGuidance")
    }
}
