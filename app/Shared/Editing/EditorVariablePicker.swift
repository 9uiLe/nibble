import AppMacros
import SwiftUI

@Equatable
struct EditorVariablePicker: View {
    private let inputRevision = UUID()
    let existing: [String]
    @SkipEquatable let insertVariable: (String) -> Bool
    @State private var name = ""
    @State private var insertionRejected = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let issue = nameIssue(trimmed)
        let canCreate = issue == nil
        let createButton = Button {
            if insertVariable(trimmed) { dismiss() }
            else { insertionRejected = true }
        } label: {
            Text("作成して追加")
                .font(.nibbleTitle)
                .foregroundStyle(canCreate ? Color.nibbleCanvas : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(canCreate ? Color.nibbleAccent : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if !canCreate {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .accessibilityHint(issue ?? "新しい印を本文に追加します")
        .accessibilityIdentifier("editor.createVariable")
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("印を追加する場所").font(.nibbleTitle)
                            Text("カーソル位置に追加。文字を選択中なら、その部分を置き換えます。")
                                .font(.nibbleBody)
                                .foregroundStyle(.secondary)
                            Text("位置がない場合は本文の末尾に追加します。")
                                .font(.nibbleBody)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("既存の変数を使う").font(.nibbleTitle)
                            if existing.isEmpty {
                                Text("まだ変数はありません。下で新しい変数を作れます。")
                                    .font(.nibbleBody)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("選ぶと同じ印を追加します。使用時に入力する値は1つです。")
                                    .font(.nibbleBody)
                                    .foregroundStyle(.secondary)
                                ForEach(existing, id: \.self) { variable in
                                    Button {
                                        if insertVariable(variable) { dismiss() }
                                        else { insertionRejected = true }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(verbatim: "{{\(variable)}}")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Spacer(minLength: 8)
                                            Text("追加")
                                                .font(.nibbleBody)
                                                .foregroundStyle(.tint)
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(.tint)
                                                .accessibilityHidden(true)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .padding(.horizontal, 12)
                                        .background(Color(uiColor: .secondarySystemBackground),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.secondary.opacity(0.35))
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("既存の変数、\(variable)を本文に追加")
                                    .accessibilityIdentifier("editor.reuseVariable.\(variable)")
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("新しい変数を作る").font(.nibbleTitle)
                            TextField("新しい変数の名前", text: $name, prompt: Text("名前を入力"))
                                .textFieldStyle(.roundedBorder)
                                .frame(minHeight: 44)
                                .focused($nameFocused)
                                .accessibilityIdentifier("editor.newVariableName")
                            if let issue, !nameFocused {
                                Text(issue)
                                    .font(.nibbleBody)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("editor.variableNameIssue")
                            }
                            if !nameFocused {
                                createButton
                            }
                            if insertionRejected && !nameFocused {
                                Text("本文の入力位置が変わりました。閉じて位置を選び直してください。")
                                    .font(.nibbleBody).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                }
                .clipped()
                if nameFocused {
                    VStack(alignment: .leading, spacing: 8) {
                        if let issue {
                            Text(issue)
                                .font(.nibbleBody)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("editor.variableNameIssue")
                        }
                        if insertionRejected {
                            Text("本文の入力位置が変わりました。閉じて位置を選び直してください。")
                                .font(.nibbleBody).foregroundStyle(.secondary)
                        }
                        createButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .background(Color.nibbleCanvas)
            .navigationTitle("変数を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("追加せず閉じる") { dismiss() }
                        .accessibilityIdentifier("editor.variablePicker.close")
                }
            }
        }
        .presentationDetents([.height(CGFloat(min(650, 440 + existing.count * 55))), .large])
        .presentationContentInteraction(.scrolls)
        .background(Color.nibbleCanvas)
    }

    private func nameIssue(_ trimmed: String) -> String? {
        if trimmed.isEmpty { return "名前を入力すると追加できます。" }
        if existing.contains(trimmed) { return "この名前は既にあります。上の行から追加してください。" }
        if trimmed.count > 40 { return "名前は40文字以内にしてください。" }
        if trimmed.contains("{") || trimmed.contains("}") || trimmed.contains("\n") || trimmed.contains("\r") {
            return "名前に波括弧と改行は使えません。"
        }
        return SnippetVariables.valid(trimmed) ? nil : "名前を確認してください。"
    }
}
