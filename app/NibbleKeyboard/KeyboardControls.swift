import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardControls: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    var body: some View {
        HStack(spacing: 8) {
            if model.needsSwitchKey { KeyboardInputModeButton(button: globe).frame(width: 44, height: 44) }
            if let notice = model.notice, notice.expires { KeyboardStatusMessage(notice: notice).font(.caption).lineLimit(2) }
            Spacer(minLength: 0)
            if model.detail == nil && model.variableUse == nil && (model.request.offset > 0 || model.page?.hasMore == true) {
                Button("前のページ", systemImage: "chevron.left") { model.movePage(forward: false) }
                    .disabled(!model.isCurrent || model.isUsing || model.request.offset == 0).accessibilityIdentifier("keyboard.previous")
                Text("\(model.request.offset / KeyboardRequest.pageSize + 1)").font(.caption.monospacedDigit())
                Button("次のページ", systemImage: "chevron.right") { model.movePage(forward: true) }
                    .disabled(!model.isCurrent || model.isUsing || model.page?.hasMore != true).accessibilityIdentifier("keyboard.next")
            }
            Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down") { model.dismiss() }.accessibilityIdentifier("keyboard.dismiss")
        }
        .labelStyle(.iconOnly).buttonStyle(KeyboardControlStyle()).padding(.horizontal, 8)
    }
}
