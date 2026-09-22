import Foundation

extension LibrarySurface {
    var title: String {
        switch self {
        case .library: "一覧"
        case .deleted: "削除した項目"
        }
    }

    var showsFilters: Bool { self == .library }
    var isRoot: Bool { self != .deleted }
}

extension LibraryRequest {
    var sectionTitle: String {
        if filter == .trash { return "削除した項目" }
        if !query.isEmpty { return "検索結果" }
        return filter == .pinned ? "ピン留めした項目" : "保存した項目"
    }
}

extension LibraryModel {
    var loadingTitle: String { surface.showsFilters ? "\(filter.title)を読み込み中" : "読み込み中" }
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
        case .deleted(let item), .restored(let item), .permanentlyDeleted(let item): item.displayTitle
        }
    }
    var announcement: String { subject.map { "\($0)、\(message)" } ?? message }
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
        if operation == .recordUse {
            if reason == .missing {
                return "本文は貼り付けて使えます。項目が完全に削除されたため、コピー回数と日時は記録できません。「閉じる」でこの案内を閉じてください。"
            }
            return "本文は貼り付けて使えます。下のボタンで、コピー回数と最後にコピーした日時の記録だけをやり直せます。\n" + recoveryMessage(retry: "")
        }
        let retry: String
        switch recovery {
        case .reload: retry = "「一覧を再読み込み」を押してください。"
        case .retryRestore: retry = "「もう一度復元する」を押してください。"
        case .dismiss, .retryUsage: retry = "この案内を閉じて、もう一度操作してください。"
        }
        return recoveryMessage(retry: retry)
    }
    private func recoveryMessage(retry: String) -> String {
        if reason == .newerVersion {
            return "nibbleを最新バージョンに更新してから、もう一度操作してください。"
        }
        return reason.localizedDescription + retry
    }
}

extension LibraryModel {
    var emptyContent: (title: String, symbol: String, message: String) {
        if isSearching {
            return ("見つかりませんでした", "magnifyingglass", "別の言葉や、短い言葉で検索してください。")
        }
        if filter == .trash {
            return ("削除した項目はありません", "trash", "削除した項目はここに表示されます。復元すると、一覧からまた使えます。")
        }
        if filter == .drafts {
            return ("下書きはありません", "square.and.pencil", "編集画面で「閉じる」を押すと、入力した内容が下書きに残ります。ここから編集を再開できます。")
        }
        if filter == .pinned {
            return ("ピン留めした項目はありません", "pin", "項目の「その他」からピン留めできます。")
        }
        return ("保存した項目はありません", "text.quote", "よく使う文章やURLを保存すると、\nいつでもコピーして使えます。")
    }
}
