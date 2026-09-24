import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @State private var showsVariablePicker = false
    @State private var focusBeforeVariables: EditorField?
    @State private var bodySelection: NSRange?
    @State private var insertionSelection: NSRange?
    @State private var insertedVariable = false
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @SkipEquatable let showPro: (() -> Void)?

    var body: some View {
        let availability = FeatureAccess.availability(.variableReplacement, pro: ProAccess.isActive())
        VStack(alignment: .leading, spacing: 12) {
            Text("本文").font(.nibbleTitle)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("末尾にペースト").font(.caption).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { texts in
                        if let text = texts.first { model.appendToBody(text) }
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(0.55)
                    .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
                    .frame(minWidth: InterfaceMetrics.touchSize, minHeight: InterfaceMetrics.touchSize)
                    .accessibilityLabel("本文の末尾にペースト")
                    .accessibilityIdentifier("editor.paste")
                }
                Spacer(minLength: 0)
                switch availability {
                case .included:
                    Button("変数を追加", systemImage: "curlybraces") {
                        focusBeforeVariables = focus.wrappedValue
                        insertionSelection = bodySelection
                        insertedVariable = false
                        focus.wrappedValue = nil
                        showsVariablePicker = true
                    }
                    .accessibilityIdentifier("editor.addVariable")
                case .requiresPro:
                    if let showPro {
                        Button("変数はPro", systemImage: "lock", action: showPro)
                            .accessibilityIdentifier("editor.variablePro")
                    } else {
                        Label("変数はPro", systemImage: "lock").foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("変数は準備中").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .tint(Color(uiColor: .secondaryLabel))
            .frame(minHeight: InterfaceMetrics.touchSize)
            MarkdownEditor(model: model, focus: focus, selection: $bodySelection)
            if !model.hasBody {
                Text("本文を入力すると保存できます。空白や改行だけでは保存できません。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.bodyRequirement")
            }
            if availability == .included {
                Text("{{宛名}}は使用時に差し替えます。保存した本文は変わりません。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsVariablePicker, onDismiss: {
            focus.wrappedValue = insertedVariable ? .body : focusBeforeVariables
        }) {
            EditorVariablePicker(existing: SnippetVariables(model.body).names,
                insertVariable: { name in
                    guard let caret = model.insertVariable(named: name, at: insertionSelection) else { return false }
                    bodySelection = caret
                    insertedVariable = true
                    return true
                })
        }
    }
}
