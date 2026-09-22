import SwiftUI

struct EditorToolbar: ToolbarContent {
    let model: EditorModel
    let taskOwner: EditorTaskOwner

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            EditorFinishButton(title: "閉じる", systemImage: "xmark", operation: .keep, model: model, taskOwner: taskOwner)
                .accessibilityIdentifier("editor.close")
        }
        ToolbarItem(placement: .confirmationAction) {
            EditorFinishButton(title: "保存", systemImage: "checkmark", prominent: true,
                               operation: .save, model: model, taskOwner: taskOwner)
                .disabled(!model.canSave)
                .accessibilityIdentifier("editor.save")
        }
    }
}
