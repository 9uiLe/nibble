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
    @SkipEquatable let proIsActive: () -> Bool
    @SkipEquatable let showPro: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if isShared { EditorSharedContentHeader() }
            EditorBodyField(model: model, focus: focus, proIsActive: proIsActive, showPro: showPro)
            EditorTitleField(model: model, focus: focus)
            if let failure = model.failure {
                EditorFailureView(model: model, taskOwner: taskOwner, failure: failure)
            }
        }
        .frame(maxWidth: 520)
        .padding(20)
        .frame(maxWidth: .infinity)
        .animationBarrier()
    }
}
