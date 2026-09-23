import AppMacros
import SwiftUI

@Equatable
struct KeyboardControls: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton

    var body: some View {
        HStack(spacing: 0) {
            if model.needsSwitchKey { KeyboardInputModeButton(button: globe).frame(width: 44, height: 44) }
            if let notice = model.notice, notice.expires {
                KeyboardStatusMessage(notice: notice)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.leading, 6)
            } else {
                Spacer(minLength: 0)
            }
            if model.detail == nil, model.request.offset > 0 || model.page?.hasMore == true {
                Button("前のページ", systemImage: "chevron.left") { model.movePage(forward: false) }
                    .disabled(!model.isCurrent || model.isUsing || model.request.offset == 0)
                    .accessibilityIdentifier("keyboard.previous")
                Text("\(model.request.offset / KeyboardRequest.pageSize + 1)").font(.caption.monospacedDigit())
                    .accessibilityLabel("\(model.request.offset / KeyboardRequest.pageSize + 1)ページ目")
                Button("次のページ", systemImage: "chevron.right") { model.movePage(forward: true) }
                    .disabled(!model.isCurrent || model.isUsing || model.page?.hasMore != true)
                    .accessibilityIdentifier("keyboard.next")
            }
            Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down", action: model.dismiss)
                .accessibilityIdentifier("keyboard.dismiss")
        }
        .font(.body).foregroundStyle(.primary)
        .labelStyle(.iconOnly).buttonStyle(KeyboardControlStyle())
        .padding(.horizontal, 10)
    }
}
