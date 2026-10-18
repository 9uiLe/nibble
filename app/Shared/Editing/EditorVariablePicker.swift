import AppMacros
import SwiftUI

@Equatable
struct EditorVariablePicker: View {
    private let inputRevision = UUID()
    let existing: [VariableName]
    @SkipEquatable let insertVariable: (VariableName) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var rejected = false

    private var issue: String? {
        switch VariableName.issue(input) {
        case .empty: return "名前を入力すると追加できます。"
        case .tooLong: return "名前は40文字以内にしてください。"
        case .unsupportedCharacter: return "名前に波括弧と改行は使えません。"
        case nil: break
        }
        guard let name = VariableName(input), existing.contains(name) else { return nil }
        return "この名前は既にあります。既存の変数から追加してください。"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("カーソル位置に印を追加します。選択中の文字は置き換え、位置が指定されていなければ末尾に追加します。")
                        .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                    Text("既存の変数を使う").font(.nibbleTitle)
                    if existing.isEmpty { Text("まだ変数はありません。下で新しく作れます。").font(.nibbleBody) }
                    ForEach(existing, id: \.self) { name in
                        Button {
                            guard insertVariable(name) else { rejected = true; return }
                            dismiss()
                        } label: {
                            HStack { Text(verbatim: name.marker); Spacer(); Label("追加", systemImage: "plus") }
                        }
                        .buttonStyle(IOSButtonStyle(.secondary, size: .compact))
                        .accessibilityIdentifier("editor.reuseVariable.\(name.text)")
                    }
                    Divider()
                    Text("新しい変数を作る").font(.nibbleTitle)
                    TextField("新しい変数の名前", text: $input).font(.nibbleTitle).textFieldStyle(.roundedBorder)
                        .frame(minHeight: 44).accessibilityIdentifier("editor.newVariableName")
                    if let issue {
                        Text(issue).font(.nibbleBody).foregroundStyle(Color.nibbleSecondary).accessibilityIdentifier("editor.variableNameIssue")
                    }
                    Button {
                        guard let name = VariableName(input), issue == nil else { return }
                        guard insertVariable(name) else { rejected = true; return }
                        dismiss()
                    } label: {
                        Text("作成して追加")
                    }
                    .buttonStyle(IOSButtonStyle())
                    .disabled(issue != nil).accessibilityIdentifier("editor.createVariable")
                    if rejected { Text("本文の入力位置が変わりました。閉じて位置を選び直してください。").font(.nibbleBody) }
                }
                .padding(20)
            }
            .navigationTitle("変数を追加").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("editor.variablePicker.close")
                }
            }
            .background(Color.nibbleCanvas)
        }
    }
}
