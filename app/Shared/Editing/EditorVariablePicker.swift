import AppMacros
import SwiftUI

@Equatable
struct EditorVariablePicker: View {
    private let inputRevision = UUID()
    let existing: [VariableName]
    @SkipEquatable let insertVariable: (VariableName) -> Bool
    @State private var name = ""
    @State private var insertionRejected = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let candidate = VariableName(name)
        let issue = nameIssue(name)
        let canCreate = candidate != nil && issue == nil
        let createButton = Button {
            guard let candidate else { return }
            if insertVariable(candidate) { dismiss() }
            else { insertionRejected = true }
        } label: {
            Text("作成して追加")
        }
        .buttonStyle(NibbleActionButtonStyle(role: .primary))
        .disabled(!canCreate)
        .accessibilityHint(issue ?? "新しい印を本文に追加します")
        .accessibilityIdentifier("editor.createVariable")
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("印を追加する場所").font(.nibbleTitle)
                            Text("カーソル位置に追加し、選択中の文字は置き換えます。位置がなければ末尾に追加します。")
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
                                            Text(verbatim: variable.marker)
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
                                    }
                                    .buttonStyle(NibbleActionButtonStyle(role: .secondary))
                                    .accessibilityLabel("既存の変数、\(variable.text)を本文に追加")
                                    .accessibilityIdentifier("editor.reuseVariable.\(variable.text)")
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
                            if let issue {
                                Text(issue)
                                    .font(.nibbleBody)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("editor.variableNameIssue")
                            }
                            createButton
                                .id("createVariable")
                            if insertionRejected {
                                Text("本文の入力位置が変わりました。閉じて位置を選び直してください。")
                                    .font(.nibbleBody).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                }
                .clipped()
                .onChange(of: nameFocused) { _, focused in
                    if focused {
                        scrollProxy.scrollTo("createVariable", anchor: .bottom)
                    }
                }
            }
            .background(Color.nibbleCanvas)
            .navigationTitle("変数を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .accessibilityHint("変数を追加せず、このシートを閉じます")
                        .accessibilityIdentifier("editor.variablePicker.close")
                }
            }
        }
        .presentationDetents([.height(CGFloat(min(650, 440 + existing.count * 55))), .large])
        .presentationContentInteraction(.scrolls)
        .background(Color.nibbleCanvas)
    }

    private func nameIssue(_ input: String) -> String? {
        switch VariableName.issue(input) {
        case .empty: return "名前を入力すると追加できます。"
        case .tooLong: return "名前は40文字以内にしてください。"
        case .unsupportedCharacter: return "名前に波括弧と改行は使えません。"
        case nil: break
        }
        if let name = VariableName(input), existing.contains(name) {
            return "この名前は既にあります。上の行から追加してください。"
        }
        return nil
    }
}
