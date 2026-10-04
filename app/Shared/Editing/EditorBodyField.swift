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
    @SkipEquatable let proIsActive: () -> Bool
    @SkipEquatable let showPro: (() -> Void)?

    var body: some View {
        let availability = FeatureAccess.availability(.variableReplacement, pro: proIsActive())
        VStack(alignment: .leading, spacing: 12) {
            MarkdownEditor(model: model, focus: focus, selection: $bodySelection)
            if !model.hasBody {
                Text(model.body.isEmpty ? "本文を入力すると保存できます。" : "空白や改行以外の本文を入力してください。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                    .accessibilityIdentifier("editor.bodyRequirement")
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                switch availability {
                case .included:
                    Button {
                        focusBeforeVariables = focus.wrappedValue
                        insertionSelection = bodySelection
                        insertedVariable = false
                        focus.wrappedValue = nil
                        showsVariablePicker = true
                    } label: {
                        Label("変数を追加", systemImage: "curlybraces")
                            .frame(minHeight: InterfaceMetrics.touchSize)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("editor.addVariable")
                case .requiresPro:
                    if let showPro {
                        Button(action: showPro) {
                            Label("変数はPro", systemImage: "lock")
                                .frame(minHeight: InterfaceMetrics.touchSize)
                                .contentShape(.rect)
                        }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("editor.variablePro")
                    } else {
                        Label("変数はPro", systemImage: "lock").foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("変数は準備中").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.nibbleSecondary)
            .tint(.nibbleSecondary)
            .frame(minHeight: InterfaceMetrics.touchSize)
            if availability == .included {
                Text("変数の値は使用時に入力します。保存した本文は変わりません。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
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
