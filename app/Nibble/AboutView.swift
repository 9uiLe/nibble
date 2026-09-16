import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("言葉を、すぐ手元に。").font(.title2.weight(.semibold))
                Text("一覧のコピーボタンで本文をコピー。項目をタップすると編集、長押しするとピン留めや削除ができます。")
            }
            Section("ほかのアプリから") {
                Text("テキストやURLの共有メニューでnibbleを選ぶと、内容を保存できます。共有先に表示されない場合は「その他」から追加してください。")
                Text("ショートカットの「URLを開く」に、一覧は nibble://library、作成は nibble://new を指定できます。ホーム画面やコントロールセンターに置くと、すぐに呼び出せます。")
            }
            Section("データについて") {
                Text("スニペットと下書きはこの端末に保存します。コピーした本文はこの端末内で利用できます。")
                Text("削除した項目は自動で消えません。「削除した項目」から復元、または完全に削除できます。アプリを削除すると保存データも失われます。")
                Text("アカウント、広告、アクセス解析はありません。")
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("nibbleについて").navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.nibbleCanvas)
    }
}

