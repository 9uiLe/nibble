import AppMacros
import SwiftUI

@Equatable
struct EditorBottomBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @Binding var confirmsDiscard: Bool
    let showHelp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if focus.wrappedValue == nil {
                Menu {
                ShareLink(item: model.body) { Label("本文を共有", systemImage: "square.and.arrow.up") }
                    .disabled(model.body.isEmpty)
                Button("下書きを破棄", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
                    .accessibilityIdentifier("editor.discard")
            } label: {
                Label("その他", systemImage: "ellipsis").modifier(IconControlStyle())
            }
                .accessibilityIdentifier("editor.more")
            }
            Spacer(minLength: 0)
            switch model.phase {
            case .finishing(let operation): ProgressView(operation.progressTitle).font(.nibbleBody)
            case .editing, .finished:
                Button(action: showHelp) {
                    HStack(spacing: 4) {
                        Text("入力と保存について").font(.nibbleBody)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(.rect)
                }
                .accessibilityIdentifier(focus.wrappedValue == nil ? "editor.help" : "editor.keyboard.help")
            }
            if focus.wrappedValue != nil {
                Button { focus.wrappedValue = nil } label: {
                    Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
                        .modifier(IconControlStyle())
                }
                .accessibilityLabel("キーボードを閉じる")
                .accessibilityIdentifier("editor.keyboard.dismiss")
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity).background(Color.nibbleCanvas)
    }
}
