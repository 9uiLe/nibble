import AppMacros
import SwiftUI

@Equatable
struct EditorFinishButton: View {
    private let inputRevision = UUID()
    let title: String
    let systemImage: String
    var prominent = false
    let operation: EditorModel.FinishOperation
    @SkipEquatable let model: EditorModel
    @SkipEquatable let taskOwner: EditorTaskOwner

    var body: some View {
        Button { taskOwner.startTask(operation, on: model) } label: {
            Label(title, systemImage: systemImage)
                .modifier(IconControlStyle(foreground: prominent ? .nibbleOnSelection : .primary,
                                           background: prominent ? .nibbleSelection : .nibbleSoft))
        }
        .buttonStyle(.plain)
        .opacity(prominent && !model.canSave ? 0.35 : 1)
    }
}
