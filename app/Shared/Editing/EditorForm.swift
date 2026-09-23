import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct EditorForm: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @SkipEquatable let taskOwner: EditorTaskOwner
    let isShared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isShared { EditorSharedContentHeader() }
            EditorTitleField(model: model, focus: focus)
            Divider()
            EditorBodyField(model: model, focus: focus)
            if let failure = model.failure {
                EditorFailureView(model: model, taskOwner: taskOwner, failure: failure)
            }
        }
        .padding(20)
        .animationBarrier()
    }
}
