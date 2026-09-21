import Foundation

enum StoreError: Error, LocalizedError, Equatable {
    case unavailable, database, newerVersion, conflict, staleDraft, missing, empty, tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: "保存先を開けませんでした。"
        case .database: "保存データを読み書きできませんでした。"
        case .newerVersion: "このデータを開くには、新しいバージョンのnibbleが必要です。"
        case .conflict: "この項目は別の操作で変更されています。"
        case .staleDraft: "この下書きは別の操作で更新されています。"
        case .missing: "この項目は削除されたか、見つからなくなりました。"
        case .empty: "本文を入力してください。空白や改行だけでは保存できません。"
        case .tooLarge: "タイトルか本文が長すぎます。短くしてから保存してください。上限はタイトル512バイト、本文1 MB（1,000,000バイト）です。どちらもUTF-8で数えます。"
        }
    }
}
