import AppMacros
import SwiftUI

@Equatable
struct EditorFailureView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let taskOwner: EditorTaskOwner
    let failure: EditorModel.Failure

    var body: some View {
        IOSInlineAlert("操作を完了できません", message: failure.message, variant: .error)
            .accessibilityIdentifier("editor.error")
        if failure.canSaveAsNew {
            Button("新しい項目として保存") { taskOwner.startTask(.saveAsNew, on: model) }
                .font(.nibbleTitle)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("editor.saveAsNew")
        }
    }
}
