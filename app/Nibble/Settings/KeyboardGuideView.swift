import AppMacros
import SwiftUI

@Equatable
struct KeyboardGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 24) {
                    KeyboardGuideSection(title: "ほかのアプリで入力する", text: "nibbleキーボードで項目をタップすると、保存した本文を入力中のアプリに挿入できます。差し替え印がある場合は、値を入力して完成文を確認してから挿入します。入力後は、そのアプリに反映されたか確認してください。下書きや削除した項目は表示されません。")
                    KeyboardIllustration()
                    KeyboardGuideSection(title: "キーボードを追加する", text: "1. iOSの「設定」を開きます。\n2.「一般」→「キーボード」→「キーボード」→「新しいキーボードを追加」でnibbleを選びます。\n3. 他のアプリで入力欄を選び、地球儀キーを長押ししてnibbleへ切り替えます。")
                }
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    Text("使うとき").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    KeyboardGuideSection(title: "全文を確認する", text: "項目の「全文」を押すと、本文を最後まで読めます。この操作では入力されません。「入力する」を押すと本文を挿入します。")
                    KeyboardGuideSection(title: "一覧を更新する", text: "「すべて」と「ピン留め」で表示する項目を選び、矢印で50件ずつ移動できます。nibbleで保存や編集をした後は、キーボードの更新ボタンを押してください。検索や編集はnibbleアプリで行います。")
                }
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    Text("許可と利用条件").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    KeyboardGuideSection(title: "コピーとピン留めを使う", text: "コピーとピン留めの変更にはフルアクセスが必要です。iOSの「設定」→「一般」→「キーボード」→「キーボード」→「nibble」で「フルアクセスを許可」をオンにしてください。本文の入力と全文の確認は、許可しなくても使えます。")
                    KeyboardGuideSection(title: "キーボードが扱うデータ", text: "nibbleキーボードは通信しません。入力先の文章や、クリップボードにある内容も読み取りません。コピーするときだけ、本文をクリップボードに書き込みます。")
                    KeyboardGuideSection(title: "利用できる入力欄", text: "パスワード欄や電話番号用の入力欄、一部のアプリでは標準キーボードへ切り替わります。入力先によっては文字数や改行が制限されます。")
                        .accessibilityIdentifier("keyboard.guide.limits")
                }
            }
            .font(.nibbleBody)
            .padding(20).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        }
        .modifier(GuidePageStyle(title: "nibbleキーボード"))
    }

}
