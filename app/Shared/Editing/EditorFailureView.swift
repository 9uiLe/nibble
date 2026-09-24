import AppMacros
import SwiftUI

@Equatable
struct EditorFailureView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let taskOwner: EditorTaskOwner
    let failure: EditorModel.Failure

    var body: some View {
        Label(failure.message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red).font(.nibbleBody)
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
