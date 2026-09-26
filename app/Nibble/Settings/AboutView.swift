import AppMacros
import SwiftUI

@Equatable
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("よく使う文章を、すぐに。")
                        .font(.nibbleTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("nibbleは、よく使う文章やURLを保存できるアプリです。必要なときにコピーしたり、nibbleキーボードから入力したりできます。")
                }

                AboutIllustration()

                AboutSection("基本の使い方") {
                    Text("**コピー・編集**　一覧のコピーボタンで本文をコピーし、使いたいアプリでペーストします。項目をタップすると編集できます。")
                    Text("**ピン留め・削除**　項目の「その他」からピン留めや削除ができます。右にスワイプするとピン留め・ピン留めを解除、左にスワイプすると削除できます。")
                }

                AboutSection("ほかのアプリから") {
                    Text("ほかのアプリで文章やURLを共有し、共有先にnibbleを選びます。内容を確認して「保存」を押してください。共有先に表示されない場合は「その他」から追加できます。")
                }

                AboutSection("ショートカットで開く") {
                    Text("ショートカットの「URLを開く」に、目的に合うURLを指定します。作ったショートカットはホーム画面やコントロールセンターに配置できます。")
                    AboutURL(title: "一覧を開く", value: "nibble://library")
                    AboutURL(title: "新しく作る", value: "nibble://new")
                }

                AboutSection("データについて") {
                    Text("保存した項目と下書きは、この端末に保存されます。コピーした本文も、この端末で使えます。ほかの端末との同期はできません。")
                    Text("削除した項目は自動で消えません。設定の「削除した項目」から復元したり、完全に削除したりできます。完全に削除した内容は元に戻せません。")
                    Text("アプリを削除すると、保存データも失われます。")
                    Text("アカウント、広告、アクセス解析はありません。")
                        .accessibilityIdentifier("about.privacy")
                    Link(destination: URL(string: "https://nibble-10d8b.web.app/privacy.html")!) {
                        HStack(spacing: 6) {
                            Text("プライバシーポリシーを読む")
                            Image(systemName: "arrow.up.right")
                                .accessibilityHidden(true)
                        }
                    }
                        .foregroundStyle(Color.nibbleAccent)
                        .accessibilityIdentifier("about.privacyPolicy")
                }
            }
            .font(.nibbleBody)
            .foregroundStyle(.primary)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .modifier(GuidePageStyle(title: "nibbleについて"))
    }
}
