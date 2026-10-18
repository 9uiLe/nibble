import Foundation

struct SnippetTextPresentation: Equatable {
    let title: String
    let hasExplicitTitle: Bool
    init(title: String, body: String, emptyTitle: String = "") {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        hasExplicitTitle = !named.isEmpty
        let fallback = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = named.isEmpty ? (fallback.isEmpty ? emptyTitle : String(fallback.prefix(60))) : named
    }
}
extension SnippetSummary {
    var textPresentation: SnippetTextPresentation { .init(title: title, body: preview) }
    var displayTitle: String { textPresentation.title }
}
extension DraftSummary {
    var textPresentation: SnippetTextPresentation { .init(title: title, body: preview, emptyTitle: "新しい下書き") }
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
        "\(SnippetText.bodyByteLimit.formatted(.number.locale(Locale(identifier: "ja_JP"))))バイト"
    }
}
enum SnippetUsagePresentation {
    static var inactiveMessage: String { "\(SnippetUsage.inactivityDays)日以上コピーしていません" }
}
extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty: "本文を入力してください。空白と改行だけでは保存できません。"
        case .tooLarge: "入力が上限を超えています。タイトルはUTF-8で\(SnippetInputLimits.title)、本文は\(SnippetInputLimits.body)まで保存できます。"
        case .conflict: "別の編集で項目が更新されています。入力を別の項目として保存できます。"
        case .staleDraft: "下書きが別の操作で更新されています。現在の入力は画面に残っています。"
        case .missing: "項目が見つかりません。削除または変更された可能性があります。"
        case .newerVersion: "新しい形式のデータです。nibbleを最新バージョンに更新してください。"
        case .unavailable: "保存先を利用できません。入力を残したまま、もう一度お試しください。"
        case .database: "保存データの読み書きに失敗しました。もう一度お試しください。"
        }
    }
}
