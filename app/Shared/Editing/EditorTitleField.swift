import AppMacros
import SwiftUI

@Equatable
struct EditorTitleField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 8) {
            Text("タイトル（任意）").font(.nibbleTitle).foregroundStyle(.secondary)
            TextField("例：お礼のメール", text: $editor.title, axis: .vertical)
                .font(.nibbleTitle)
                .focused(focus, equals: .title)
                .accessibilityIdentifier("editor.title")
                .accessibilityLabel("タイトル（任意）")
            Text("一覧で見つけるための名前です。")
                .font(.nibbleBody).foregroundStyle(.secondary)
        }
    }
}
