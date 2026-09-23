import AppMacros
import SwiftUI

@Equatable
struct EditorHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("末尾にペースト").font(.nibbleTitle)
                        Text("テキストをコピーすると使えます。コピーした内容を、本文の末尾にそのまま追加します。")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markdownで入力").font(.nibbleTitle)
                        Text("「プレビュー」に切り替えると、Markdownの記号を隠して見出し・太字・斜体・コードなどの見た目を確認できます。「入力」に戻ると、原文の編集を続けられます。Markdownの記号も、空白や改行と一緒にそのまま保存・コピーされます。")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("入力の上限").font(.nibbleTitle)
                        Text("タイトルは任意で\(SnippetInputLimits.title)まで、本文は\(SnippetInputLimits.body)まで入力できます。")
                            .accessibilityIdentifier("editor.lengthLimit")
                        Text("UTF-8で数えるため、文字によって使うバイト数が異なります。空白や改行は、そのまま保存されます。")
                        Text("本文が空、または空白や改行だけの場合は保存できません。")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("保存と下書き").font(.nibbleTitle)
                        Text("「保存」を押すと、一覧やキーボードから使えます。")
                        Text("「閉じる」を押すと、入力した内容が下書きに残ります。空の新規入力や、変更していない項目は下書きに残りません。")
                        Text("下書きは一覧の「下書き」から再開できます。不要な下書きは、編集画面の「その他」から破棄できます。保存済みの項目は変わりません。")
                    }
                }
                .font(.nibbleBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color.nibbleCanvas)
            .navigationTitle("入力の上限と保存について")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label("編集に戻る", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("編集に戻る")
                    .accessibilityIdentifier("editor.help.close")
                }
            }
        }
        .tint(.nibbleAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .animationBarrier()
    }
}
