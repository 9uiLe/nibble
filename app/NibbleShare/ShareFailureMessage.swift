import Foundation

enum ShareFailureMessage {
    static func text(for error: Error) -> String {
        let action = "「閉じる」で共有元へ戻れます。"
        switch error {
        case ShareError.unsupported:
            return "この内容は取り込めません。文章またはURLを選んで共有してください。" + action
        case StoreError.empty:
            return "共有された文章は空白や改行だけです。共有元で文章を選び直してください。" + action
        case StoreError.tooLarge:
            return "文章が長すぎます。本文はUTF-8で\(SnippetInputLimits.body)まで保存できます。共有元で短くしてから共有してください。" + action
        case StoreError.newerVersion:
            return "nibbleを最新バージョンに更新してから、もう一度共有してください。" + action
        case is StoreError:
            return "共有した内容を下書きに保存できませんでした。共有元に戻り、もう一度共有してください。" + action
        default:
            return "共有元から内容を読み込めませんでした。もう一度共有してください。" + action
        }
    }
}
