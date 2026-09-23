import Foundation
extension EditorModel.FinishOperation {
    var progressTitle: String {
        switch self {
        case .save, .saveAsNew: "保存中"
        case .keep: "下書きを保存中"
        case .discard: "下書きを破棄中"
        }
    }
}

extension EditorModel.Failure {
    var message: String {
        let title: String
        let retry: String
        switch operation {
        case .save, .saveAsNew:
            title = "保存できませんでした。"
            retry = operation == .saveAsNew ? "「新しい項目として保存」をもう一度押してください。" : "「保存」をもう一度押してください。"
        case .keep:
            title = "下書きを保存できなかったため、閉じられませんでした。"
            retry = "「閉じる」をもう一度押してください。"
        case .discard:
            title = "下書きを破棄できませんでした。"
            retry = "「その他」から「下書きを破棄」をもう一度選んでください。"
        case nil:
            title = "下書きを自動保存できませんでした。"
            retry = "「保存」または「閉じる」を押して、もう一度保存してください。"
        }
        let reason = self.reason.localizedDescription
        let recovery: String
        switch self.recovery {
        case .saveAsNew: recovery = "「新しい項目として保存」で、この画面の内容を別の項目に保存できます。"
        case .correctInput: recovery = ""
        case .updateApplication: recovery = "入力をコピーして別の場所に控えてから、nibbleを更新してください。"
        case .retry: recovery = retry
        case .upgrade: recovery = "Proに登録するか、保存済み項目を減らしてから保存してください。"
        }
        return title + "入力はこの画面に残っています。\n" + reason + recovery
    }
}
