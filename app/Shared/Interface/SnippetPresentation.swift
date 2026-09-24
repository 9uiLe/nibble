import Foundation

/// Formatting is a projection of original text; it never becomes editable input.
struct SnippetTextPresentation: Equatable {
    let title: String
    let hasExplicitTitle: Bool

    init(title: String, body: String, emptyTitle: String = "") {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        hasExplicitTitle = !heading.isEmpty
        let value = hasExplicitTitle ? heading : String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        self.title = value.isEmpty ? emptyTitle : value
    }
}

extension SnippetSummary {
    var textPresentation: SnippetTextPresentation { SnippetTextPresentation(title: title, body: preview) }
    var displayTitle: String { textPresentation.title }
}

extension DraftSummary {
    var textPresentation: SnippetTextPresentation {
        SnippetTextPresentation(title: title, body: preview, emptyTitle: "新しい下書き")
    }
    var displayTitle: String { textPresentation.title }
}

extension LibraryFilter {
    var title: String {
        switch self {
        case .all: "すべて"
        case .pinned: "ピン留め"
        case .drafts: "下書き"
        case .trash: "削除した項目"
        }
    }
}

enum SnippetInputLimits {
    static var title: String { "\(SnippetText.titleByteLimit)バイト" }
    static var body: String {
        let bytes = SnippetText.bodyByteLimit
        let count = bytes.formatted(.number.locale(Locale(identifier: "ja_JP")))
        return bytes.isMultiple(of: 1_000_000) ? "\(bytes / 1_000_000) MB（\(count)バイト）" : "\(count)バイト"
    }
}

enum SnippetUsagePresentation {
    static var inactiveMessage: String { "\(SnippetUsage.inactivityDays)日以上コピーしていません" }
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable: "保存先を開けませんでした。"
        case .database: "保存データを読み書きできませんでした。"
        case .newerVersion: "このデータを開くには、新しいバージョンのnibbleが必要です。"
        case .conflict: "この項目は別の操作で変更されています。"
        case .staleDraft: "この下書きは別の操作で更新されています。"
        case .missing: "この項目は削除されたか、見つからなくなりました。"
        case .empty: "本文を入力してください。空白や改行だけでは保存できません。"
        case .tooLarge: "タイトルか本文が長すぎます。短くしてから保存してください。上限はタイトル\(SnippetInputLimits.title)、本文\(SnippetInputLimits.body)です。どちらもUTF-8で数えます。"
        }
    }
}
