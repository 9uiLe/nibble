import Foundation

extension LibrarySurface {
    var title: String { self == .library ? "一覧" : "削除した項目" }
    var showsFilters: Bool { self == .library }
    var isRoot: Bool { self == .library }
}
extension LibraryRequest {
    var sectionTitle: String {
        if filter == .trash { return "削除した項目" }
        if !query.isEmpty { return "検索結果" }
        if filter == .drafts { return "編集中の項目" }
        return filter == .pinned ? "ピン留めした項目" : "保存した項目"
    }
}
extension LibraryModel {
    var loadingTitle: String { "\(filter.title)を読み込み中" }
    var emptyContent: (title: String, symbol: String, message: String) {
        if isSearching { return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い言葉で検索してください。") }
        switch filter {
        case .all: return ("保存した項目はありません", "text.quote", "よく使う文章やURLを保存すると、\nいつでもコピーして使えます。")
        case .pinned: return ("ピン留めした項目はありません", "pin", "項目の「その他」からピン留めできます。")
        case .drafts: return ("下書きはありません", "square.and.pencil", "編集画面で「閉じる」を押すと、入力した内容が下書きに残ります。ここから編集を再開できます。")
        case .trash: return ("削除した項目はありません", "trash", "削除した項目はここに表示されます。復元すると、一覧からまた使えます。")
        }
    }
}
extension LibraryModel.Notice {
    var message: String {
        switch result {
        case .copied: "コピーしました"
        case .deleted: "削除しました"
        case .restored: "元に戻しました"
        case .permanentlyDeleted: "完全に削除しました"
        }
    }
    var subject: String? {
        switch result {
        case .copied: nil
        case .deleted(let row), .restored(let row), .permanentlyDeleted(let row): row.displayTitle
        }
    }
    var announcement: String { [subject, message].compactMap { $0 }.joined(separator: "、") }
}
extension LibraryModel.Failure {
    var title: String {
        switch operation {
        case .load: "一覧を読み込めませんでした"
        case .open: "編集を始められませんでした"
        case .copy: "コピーできませんでした"
        case .pin: "ピン留めを変更できませんでした"
        case .delete: "削除できませんでした"
        case .restore: "復元できませんでした"
        case .permanentlyDelete: "完全に削除できませんでした"
        case .notice: "通知を更新できませんでした"
        case .recordUse: "コピー済みですが、回数と日時を記録できませんでした"
        }
    }
    var message: String {
        if operation == .recordUse { return "本文は貼り付けて使えます。再コピーせず、記録だけをやり直せます。\n" + reason.localizedDescription }
        return reason.localizedDescription
    }
}
