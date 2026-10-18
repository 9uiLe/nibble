import AppMacros
import SwiftUI

@Equatable
struct EditorHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("保存と下書き").font(.nibbleTitle)
                    Text("「保存」で一覧とキーボードから使える項目になります。「閉じる」は入力を下書きに残します。空の新規入力と変更していない項目は下書きに残りません。")
                    Text("入力の上限").font(.nibbleTitle)
                    Text("タイトルは任意で\(SnippetInputLimits.title)まで、本文は\(SnippetInputLimits.body)まで入力できます。")
                        .accessibilityIdentifier("editor.lengthLimit")
                    Text("UTF-8のバイト数で数えます。空白や改行だけの本文は保存できません。")
                    Text("Markdownで入力").font(.nibbleTitle)
                    Text("見出し・太字・斜体・コード・引用・リンク・取り消し線を表示できます。「プレビュー」で記号を隠して読み、「入力」で続きを編集します。記号・空白・改行もそのまま保存・コピーします。")
                    Text("不要な下書き").font(.nibbleTitle)
                    Text("「その他」から「下書きを破棄」を選びます。保存済みの項目は変わりません。")
                }
                .font(.nibbleBody).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.nibbleCanvas)
            .navigationTitle("入力と保存について").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("編集に戻る") { dismiss() }.accessibilityIdentifier("editor.help.close")
                }
            }
        }
    }
}
