import Foundation

extension EditorModel.FinishOperation {
    var progressTitle: String {
        switch self {
        case .discard: "下書きを破棄中"
        case .keep: "下書きを保存中"
        case .save, .saveAsNew: "保存中"
        }
    }
}

extension EditorModel.Failure {
    var message: String {
        let introduction: String
        switch operation {
        case .keep: introduction = "下書きを保存できなかったため、閉じられませんでした。"
        case .discard: introduction = "下書きを破棄できませんでした。"
        case .save, .saveAsNew: introduction = "保存できませんでした。"
        case nil: introduction = "下書きを自動保存できませんでした。"
        }
        let action: String
        switch recovery {
        case .saveAsNew: action = "「新しい項目として保存」で、この入力を別の項目に保存できます。"
        case .correctInput: action = "入力を修正してから保存してください。"
        case .updateApplication: action = "入力を別の場所に控えてから、nibbleを更新してください。"
        case .retry: action = "「保存」または「閉じる」で、もう一度保存できます。"
        }
        return introduction + "\n" + reason.localizedDescription + "\n" + action
    }
}
