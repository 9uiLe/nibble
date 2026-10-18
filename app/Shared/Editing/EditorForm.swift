import AppMacros
import ScopedAnimation
import SwiftUI

@Equatable
struct EditorForm: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @SkipEquatable let taskOwner: EditorTaskOwner
    let isShared: Bool
    @SkipEquatable let proIsActive: () -> Bool

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 24) {
            if isShared {
                Label("共有された内容を確認して保存できます。", systemImage: "square.and.arrow.down")
                    .font(.nibbleBody)
            }
            EditorBodyField(model: model, focus: focus, proIsActive: proIsActive)
            VStack(alignment: .leading, spacing: 8) {
                Text("タイトル（任意）").font(.nibbleTitle)
                TextField("タイトル", text: $editor.title)
                    .font(.nibbleTitle)
                    .focused(focus, equals: .title).textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44).accessibilityIdentifier("editor.title")
            }
            if let failure = model.failure {
                VStack(alignment: .leading, spacing: 8) {
                    IOSInlineAlert("入力はこの画面に残っています", message: failure.message, variant: .error)
                        .accessibilityIdentifier("editor.error")
                    if failure.canSaveAsNew {
                        Button { taskOwner.startTask(.saveAsNew, on: model) } label: {
                            Text("新しい項目として保存")
                        }
                        .buttonStyle(IOSButtonStyle(.secondary, size: .compact))
                        .accessibilityIdentifier("editor.saveAsNew")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .animationBarrier()
    }
}
