import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @SkipEquatable let proIsActive: () -> Bool
    @State private var selection: NSRange?
    @State private var capturedSelection: NSRange?
    @State private var previousFocus: EditorField?
    @State private var picker = false
    @State private var inserted = false

    var body: some View {
        let access = FeatureAccess.availability(.variableReplacement, pro: proIsActive())
        VStack(alignment: .leading, spacing: 12) {
            MarkdownEditor(model: model, focus: focus, selection: $selection)
            if !model.hasBody {
                Text(model.body.isEmpty ? "本文を入力すると保存できます。" : "空白や改行以外の本文を入力してください。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary).accessibilityIdentifier("editor.bodyRequirement")
            }
            HStack {
                Text("値は使う直前に入力します。").font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                Spacer(minLength: 8)
                Button {
                    capturedSelection = selection
                    previousFocus = focus.wrappedValue
                    inserted = false
                    focus.wrappedValue = nil
                    picker = true
                } label: { Label("変数を追加", systemImage: "curlybraces").frame(minHeight: 44).contentShape(.rect) }
                .buttonStyle(.plain).disabled(!access.isAvailable).accessibilityIdentifier("editor.addVariable")
            }
            if !access.isAvailable {
                Text("変数の利用は現在準備中です。印を含む原文は保存できます。").font(.nibbleBody)
            }
        }
        .sheet(isPresented: $picker, onDismiss: { focus.wrappedValue = inserted ? .body : previousFocus }) {
            EditorVariablePicker(existing: SnippetVariables(model.body).names) { name in
                guard let caret = model.insertVariable(named: name, at: capturedSelection) else { return false }
                selection = caret
                inserted = true
                return true
            }
        }
    }
}
