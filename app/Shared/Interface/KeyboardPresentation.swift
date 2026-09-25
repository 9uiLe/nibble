import Foundation

extension KeyboardFilter {
    var title: String { libraryFilter.title }
}

extension KeyboardModel {
    var message: String? { notice?.result.text }
    var failure: String? { loadFailure?.text }
}

extension KeyboardModel.Detail {
    var failure: String? { error?.text }
}

extension KeyboardModel.Notice {
    var message: String { result.text }
}

extension KeyboardModel.Message {
    var text: String {
        switch self {
        case .cancelled: "読み込みを中断しました。再読み込みを押してください。"
        case .requiresFullAccess(let action):
            "\(action == .copy ? "コピー" : "ピン留めの変更")にはフルアクセスが必要です。nibbleの「設定」→「nibbleキーボード」で設定方法を確認してください。"
        case .inputChanged: "入力位置が変わったため、本文を送っていません。入力先を確認して、項目をもう一度選んでください。"
        case .inserted: "本文を送りました"
        case .copied: "コピーしました"
        case .pinChanged(let pinned): pinned ? "ピン留めしました" : "ピン留めを解除しました"
        case .failed(let action, let reason, let detailIsOpen):
            action.failureTitle + reason.message(detailIsOpen: detailIsOpen)
        }
    }
}

extension KeyboardModel.Action {
    fileprivate var failureTitle: String {
        switch self {
        case .load: "一覧を読み込めませんでした。"
        case .insert: "本文を送れませんでした。"
        case .copy: "コピーできませんでした。"
        case .preview: "本文を読み込めませんでした。"
        case .pin: "ピン留めを変更できませんでした。"
        case .reloadAfterPin: "ピン留めは変更しましたが、一覧を更新できませんでした。"
        case .changed: ""
        }
    }
}

extension KeyboardModel.Reason {
    fileprivate func message(detailIsOpen: Bool) -> String {
        if self == .store(.newerVersion) { return "nibbleを最新バージョンに更新してください。" }
        if self == .notPrepared { return KeyboardReadError.notPrepared.localizedDescription }
        let reason: String
        switch self {
        case .store(let error): reason = error.localizedDescription
        case .changed: reason = "項目が変更されています。"
        case .notPrepared, .unavailable: reason = "保存データを読み込めませんでした。"
        }
        return reason + (detailIsOpen ? "「一覧に戻る」を押してから、再読み込みを押してください。" : "再読み込みを押してください。")
    }
}

extension KeyboardReadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notPrepared: "nibbleで文章やURLを保存してから、キーボードを開き直してください。"
        case .changed: "項目が変更されています。一覧を読み直して選び直してください。"
        }
    }
}
