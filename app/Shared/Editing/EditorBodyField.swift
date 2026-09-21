import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本文").font(.nibbleTitle).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Text("末尾にペースト").font(.caption).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { texts in
                        if let text = texts.first { model.body += text }
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonBorderShape(.circle)
                    .frame(width: 36, height: 36)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("本文の末尾にペースト")
                    .accessibilityIdentifier("editor.paste")
                }
            }
            if !model.hasBody {
                Text("本文を入力すると保存できます。空白や改行だけでは保存できません。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.bodyRequirement")
            }
            // A growing native multiline field lets the entire page scroll on small screens.
            TextField("保存したい文章やURLを入力", text: $editor.body, axis: .vertical)
                .font(.nibbleBody)
                .lineLimit(10...)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: .body)
                .accessibilityIdentifier("editor.body")
                .accessibilityLabel("本文")
        }
    }
}
