import AppMacros
import SwiftUI

@Equatable
struct EditorVariablePicker: View {
    private let inputRevision = UUID()
    let existing: [String]
    @SkipEquatable let appendVariable: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !existing.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("既存の変数を再利用").font(.nibbleTitle)
                            ForEach(existing, id: \.self) { variable in
                                Button {
                                    appendVariable(variable)
                                    dismiss()
                                } label: {
                                    Text(verbatim: variable)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("editor.reuseVariable.\(variable)")
                                Divider()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新しい変数を作成").font(.nibbleTitle)
                        TextField("例：宛名", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("editor.newVariableName")
                        if existing.contains(trimmed) {
                            Text("この名前は既にあります。上の一覧から選んでください。")
                                .font(.nibbleBody).foregroundStyle(.secondary)
                        } else {
                            Text("名前は40文字以内。本文の末尾に印を追加します。")
                                .font(.nibbleBody).foregroundStyle(.secondary)
                        }
                        Button("作成して追加") {
                            appendVariable(trimmed)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!SnippetVariables.valid(trimmed) || existing.contains(trimmed))
                        .accessibilityIdentifier("editor.createVariable")
                    }
                    if !existing.isEmpty {
                        Text("同じ変数を再利用すると、使用時に入力する値は1つです。")
                            .font(.nibbleBody).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("変数を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .background(Color.nibbleCanvas)
    }
}
