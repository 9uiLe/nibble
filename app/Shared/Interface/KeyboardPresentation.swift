import Foundation

extension KeyboardFilter { var title: String { libraryFilter.title } }
extension KeyboardModel {
    var message: String? { notice?.result.text }
    var failure: String? { loadFailure?.text }
}
extension KeyboardModel.Detail { var failure: String? { error?.text } }
extension KeyboardModel.Notice { var message: String { result.text } }
extension KeyboardModel.Message {
    var text: String {
        switch self {
        case .copied: "コピーしました"
        case .inserted: "本文を送りました"
        case .pinChanged(let value): value ? "ピン留めしました" : "ピン留めを解除しました"
        case .inputChanged: "入力先が変わりました。本文は送っていません。入力先を確認して、もう一度選んでください。"
        case .cancelled: "読み込みを中断しました。再読み込みで続けられます。"
        case .requiresFullAccess(let action):
            "\(action == .copy ? "コピー" : "ピン留めの変更")にはフルアクセスが必要です。本体の設定から「nibbleキーボード」の案内を確認してください。全文確認と入力は許可なしで使えます。"
        case .failed(let action, let reason, let open):
            action.failureHeading + reason.explanation + (open ? " 一覧に戻って再読み込みしてください。" : " 再読み込みしてください。")
        }
    }
}
extension KeyboardModel.Action {
    fileprivate var failureHeading: String {
        switch self {
        case .load: "一覧を読み込めませんでした。"
        case .preview: "全文を読み込めませんでした。"
        case .copy: "コピーできませんでした。"
        case .insert: "本文を送れませんでした。"
        case .pin: "ピン留めを変更できませんでした。"
        case .reloadAfterPin: "ピン留めは変更しましたが、一覧を更新できませんでした。"
        case .changed: "項目が変更されています。"
        }
    }
}
extension KeyboardModel.Reason {
    fileprivate var explanation: String {
        switch self {
        case .notPrepared: "本体で文章やURLを保存してからキーボードを開いてください。"
        case .store(let error): error.localizedDescription
        case .changed: "一覧を読み直して対象を確認してください。"
        case .unavailable: "保存データを利用できません。"
        }
    }
}
extension KeyboardReadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notPrepared: "本体で文章やURLを保存してからキーボードを開いてください。"
        case .changed: "項目が変更されています。再読み込みして選び直してください。"
        }
    }
}
