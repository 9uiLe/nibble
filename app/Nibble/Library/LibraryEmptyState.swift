import AppMacros
import SwiftUI

@Equatable
struct LibraryEmptyState: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let showsFilters: Bool
    let showsCreationCTA: Bool

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(emptyContent.title).font(.nibbleTitle)
            } icon: {
                Image(systemName: emptyContent.symbol)
            }
        } description: {
            Text(emptyContent.message)
                .font(.nibbleBody)
        } actions: {
            if showsCreationCTA {
                Button("新しく作る") { taskOwner.startTask(.open(.new), on: model) }
                    .font(.nibbleTitle)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityIdentifier("library.createFirst")
                    .keyboardShortcut("n", modifiers: .command)
            } else if showsFilters && model.filter == .pinned {
                Button("すべてを見る") { model.filter = .all }
                    .font(.nibbleTitle)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier("library.showAll")
            }
        }
        .padding(.vertical, 30)
        .listRowSeparator(.hidden)
    }
    private var emptyContent: (title: String, symbol: String, message: String) {
        if !model.query.isEmpty {
            return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い言葉で検索してください。")
        }
        if model.filter == .trash {
            return ("削除した項目はありません", "trash", "削除した項目はここに表示されます。復元すると、一覧からまた使えます。")
        }
        if model.filter == .drafts {
            return ("下書きはありません", "square.and.pencil", "編集画面で「閉じる」を押すと、入力した内容が下書きに残ります。ここから編集を再開できます。")
        }
        if model.filter == .pinned {
            return ("ピン留めした項目はありません", "pin", "項目の「その他」からピン留めできます。")
        }
        return ("保存した項目はありません", "text.quote", "よく使う文章やURLを保存すると、\nいつでもコピーして使えます。")
    }
}
