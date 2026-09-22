import Foundation

enum ShareFailureMessage {
    static func text(for error: Error) -> String {
        switch error {
        case ShareError.unsupported:
            "文章またはURLを選んで共有してください。「閉じる」で共有元のアプリに戻れます。"
        case StoreError.empty:
            "共有する文章が空です。共有元のアプリで、空白や改行以外の文字を選んで共有してください。"
        case StoreError.tooLarge:
            "共有する文章が長すぎます。共有元のアプリで短くしてから、もう一度共有してください。本文の上限はUTF-8で\(SnippetInputLimits.body)です。"
        case StoreError.newerVersion:
            "nibbleを最新バージョンに更新してから、もう一度共有してください。"
        case is StoreError:
            "共有した内容を下書きに保存できませんでした。「閉じる」で共有元のアプリに戻り、もう一度共有してください。"
        default:
            "共有元のアプリから内容を読み込めませんでした。「閉じる」で戻り、もう一度共有してください。"
        }
    }
}
