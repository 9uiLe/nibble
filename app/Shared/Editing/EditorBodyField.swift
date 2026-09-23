import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @State private var showsVariableName = false
    @State private var variableName = ""
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本文").font(.nibbleTitle).foregroundStyle(.secondary)
                Spacer()
                if FeatureAccess.allows(.variableReplacement, pro: ProAccess.isActive()) {
                    Button("変数を追加", systemImage: "curlybraces") {
                        variableName = ""
                        showsVariableName = true
                    }
                    .font(.caption)
                    .frame(minHeight: InterfaceMetrics.touchSize)
                    .accessibilityIdentifier("editor.addVariable")
                }
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
            if FeatureAccess.allows(.variableReplacement, pro: ProAccess.isActive()) {
                Text("{{宛名}}のような印を本文に追加します。コピー・入力の直前に内容を指定できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .alert("差し替える項目の名前", isPresented: $showsVariableName) {
            TextField("例：宛名", text: $variableName)
            Button("追加") {
                let name = variableName.trimmingCharacters(in: .whitespaces)
                guard SnippetVariables.valid(name) else { return }
                model.appendToBody("{{\(name)}}")
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("40文字以内の名前を入力してください。同じ名前は利用時に一度だけ入力します。")
        }
    }
}
