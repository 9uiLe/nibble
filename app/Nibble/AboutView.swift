import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("言葉を、すぐ手元に。")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("よく使う言葉を保存して、必要なときに探してコピーする。nibbleは、あなたの言葉を手元に置く道具です。")
                }

                AboutIllustration()

                AboutSection("基本の使い方") {
                    Text("**コピー・編集**　一覧のコピーボタンで本文をコピーし、使いたいアプリでペーストします。項目をタップすると編集できます。")
                    Text("**ピン留め・削除**　項目を右にスワイプするとピン留め・解除、左にスワイプすると削除できます。各行の「その他」からも操作できます。")
                }

                AboutSection("ほかのアプリから") {
                    Text("テキストやURLの共有メニューでnibbleを選ぶと、内容を保存できます。共有先に表示されない場合は「その他」から追加してください。")
                }

                AboutSection("ショートカットで開く") {
                    Text("ショートカットの「URLを開く」に、目的に合うURLを指定します。作ったショートカットはホーム画面やコントロールセンターに配置できます。")
                    AboutURL(title: "一覧を開く", value: "nibble://library")
                    AboutURL(title: "新規作成を開く", value: "nibble://new")
                }

                AboutSection("データについて") {
                    Text("スニペットと下書きは、この端末に保存します。コピーした本文も、この端末内で利用できます。同期機能はありません。")
                    Text("削除した項目は自動で消えません。設定の「削除した項目」から復元、または完全に削除できます。完全に削除した内容は元に戻せません。")
                    Text("アプリを削除すると、保存データも失われます。")
                    Text("アカウント、広告、アクセス解析はありません。")
                        .accessibilityIdentifier("about.privacy")
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .navigationTitle("nibbleについて")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.nibbleCanvas)
    }
}

private struct AboutSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct AboutURL: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            Text(value)
                .monospaced()
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
