import AppMacros
import SwiftUI

@Equatable
struct EditorExitGuidance: @MainActor EquatableBodyView {
    let isShared: Bool

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isShared {
                Text("閉じると下書きを残して共有元へ。保存すると使えます。")
            } else {
                Text("閉じると下書きに残り、保存すると使えます。")
            }
        }
        .font(.nibbleBody).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.nibbleCanvas)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.exitGuidance")
    }
}
