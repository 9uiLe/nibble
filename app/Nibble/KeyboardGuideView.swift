import AppMacros
import SwiftUI

@Equatable
struct KeyboardGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("他のアプリで使う", text: "nibbleキーボードで保存済みの項目をタップすると、入力中のアプリへ本文を挿入できます。下書きや削除した項目は表示しません。")
                section("キーボードを追加する", text: "1. iOSの「設定」を開きます。\n2.「一般」→「キーボード」→「キーボード」→「新しいキーボードを追加」でnibbleを選びます。\n3. 他のアプリで入力欄を選び、地球儀キーを長押ししてnibbleへ切り替えます。")
                section("全文・コピー・ピン留め", text: "行の「…」から全文を確認できます。キーボード設定のnibbleで「フルアクセスを許可」をオンにすると、詳細のコピーとピン留めを使えます。直接挿入と全文確認には不要です。nibbleキーボードは通信せず、入力先の文章やクリップボードを読み取りません。")
                section("一覧を更新する", text: "「すべて」と「ピン留め」で絞り込み、矢印で50件ずつ移動できます。保存や編集をした後は更新ボタンを押してください。管理や検索はnibble本体で行います。")
                section("利用できる入力欄", text: "パスワード欄や電話番号用の入力欄、一部のアプリでは標準キーボードへ切り替わります。入力先によっては文字数や改行が制限されます。")
            }
            .padding(20).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color.nibbleCanvas)
        .navigationTitle("nibbleキーボード")
        .toolbarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
