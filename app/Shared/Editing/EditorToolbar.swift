import SwiftUI

struct EditorToolbar: ToolbarContent {
    let model: EditorModel
    let taskOwner: EditorTaskOwner
    let focus: FocusState<EditorField?>.Binding
    let confirmsDiscard: Binding<Bool>
    let showHelp: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            EditorFinishButton(title: "閉じる", systemImage: "xmark", operation: .keep, model: model, taskOwner: taskOwner)
                .accessibilityIdentifier("editor.close")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .confirmationAction) {
            EditorFinishButton(title: "保存", systemImage: "checkmark", prominent: true,
                               operation: .save, model: model, taskOwner: taskOwner)
                .disabled(!model.canSave)
                .accessibilityIdentifier("editor.save")
        }
        .sharedBackgroundVisibility(.hidden)
        if focus.wrappedValue == nil {
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    ShareLink(item: model.body) { Label("本文を共有", systemImage: "square.and.arrow.up") }
                        .disabled(model.body.isEmpty)
                    Button("下書きを破棄", systemImage: "trash", role: .destructive) { confirmsDiscard.wrappedValue = true }
                        .accessibilityIdentifier("editor.discard")
                } label: {
                    Label("その他", systemImage: "ellipsis")
                        .modifier(IconControlStyle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("その他")
                .accessibilityIdentifier("editor.more")
                Spacer()
                if case .finishing(let operation) = model.phase {
                    ProgressView {
                        Text(operation.progressTitle).font(.nibbleBody)
                    }
                } else {
                    Button { showHelp() } label: {
                        Label("入力の上限と保存について", systemImage: "info")
                            .modifier(IconControlStyle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor.help")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
