import AppMacros
import SwiftUI

@MainActor @Equatable
struct WorkspaceSettingsView: View {
    private let inputRevision = UUID()
    @SkipEquatable let storage: any WorkspaceStorage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("文章を用意して使う") {
                    Text("作成した文章を保存し、名前や本文から探します。文章を選び、完成文を確認してコピーします。使いたいアプリに戻り、入力欄を選んでペーストしてください。")
                        .accessibilityIdentifier("workspace.settings.copyGuide")
                    Text("他のアプリで選んだ文章やURLは、共有のnibbleから取り込めます。閉じた作業は一覧の「作業中」から再開できます。")
                    Text("編集画面で「差し替えを使う」をオンにして {{宛名}} のような印を入れると、使うときに値を指定できます。オフなら、印も含めて本文を文字どおりに使います。")
                }
                Section("よく使う固定文をキーボードで使う") {
                    Text("ピン留めした固定文を最大50件、入力先で確認して挿入できます。「差し替えを使う」がオンで印がある文章や、ここに出ない文章は、本体で探してコピーしてください。\n\niPhoneの「設定」→「一般」→「キーボード」→「キーボード」→「新しいキーボードを追加」でnibbleを追加します。入力欄で地球儀を長押ししてnibbleを選びます。")
                        .accessibilityIdentifier("workspace.settings.keyboardGuide")
                    Text("フルアクセスは不要です。通常の日本語入力へ戻るときも、地球儀から切り替えます。パスワード欄やキーボードを許可しないアプリでは、コピーとペーストを使ってください。")
                }
                Section("文章の管理") {
                    NavigationLink("ごみ箱から文章を戻す") { WorkspaceTrashView(storage: storage) }
                        .accessibilityIdentifier("workspace.trash")
                    Text("ごみ箱へ移した文章も、作業中の入力も、この端末内に保持します。アプリを削除するとデータも失われます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("文章とデータ") {
                    Text("本文と作業中の入力は端末内に保存します。nibbleは通信せず、他のアプリの入力履歴やクリップボードを読み取りません。コピーした文章は、この端末のクリップボードへ渡します。")
                        .accessibilityIdentifier("workspace.settings.privacy")
                    Text("データはiPhoneのバックアップに含まれる場合があります。コピー後の文章は、貼り付け先のアプリの扱いに従います。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("課金・広告・作業を遮る演出はありません。")
                    Link("プライバシーポリシー", destination: URL(string: "https://nibble-10d8b.web.app/privacy.html")!)
                    Link("サポート", destination: URL(string: "https://nibble-10d8b.web.app/support.html")!)
                }
            }
            .navigationTitle("使い方と管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("workspace.settings.close")
                }
            }
        }
    }
}
