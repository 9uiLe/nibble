import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本文").font(.nibbleTitle).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Text("末尾にペースト").font(.caption).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { texts in
                        if let text = texts.first { model.appendToBody(text) }
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonBorderShape(.circle)
                    .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
                    .frame(minWidth: InterfaceMetrics.touchSize, minHeight: InterfaceMetrics.touchSize)
                    .accessibilityLabel("本文の末尾にペースト")
                    .accessibilityIdentifier("editor.paste")
                }
            }
            if !model.hasBody {
                Text("本文を入力すると保存できます。空白や改行だけでは保存できません。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.bodyRequirement")
            }
            MarkdownEditor(model: model, focus: focus)
        }
    }
}
