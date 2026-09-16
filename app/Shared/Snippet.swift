import Foundation
import Darwin

struct Snippet: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var pinned: Bool
    var revision: Int
    var updatedAt: Date
    var deleted: Bool

    var displayTitle: String { Self.displayTitle(title: title, body: body) }

    static func displayTitle(title: String, body: String) -> String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) : heading
    }
}

struct SnippetSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let pinned: Bool
    let revision: Int
    var displayTitle: String { Snippet.displayTitle(title: title, body: preview) }
}

enum LibraryFilter: String, CaseIterable, Sendable {
    case all, pinned, trash
    var title: String {
        switch self {
        case .all: "すべて"
        case .pinned: "ピン留め"
        case .trash: "削除した項目"
        }
    }
}

enum StoreError: Error, LocalizedError, Equatable {
    case unavailable, database, newerVersion, conflict, staleDraft, missing, empty, tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: "保存先を開けませんでした。アプリを開き直して再試行してください。"
        case .database: "保存データにアクセスできませんでした。内容を保持して、もう一度お試しください。"
        case .newerVersion: "このデータを開くには、新しいバージョンのnibbleが必要です。"
        case .conflict: "この項目は別の操作で変更されています。編集中の内容を新しい項目として保存できます。"
        case .staleDraft: "この下書きには新しい入力があります。編集中の内容を新しい項目として保存できます。"
        case .missing: "この項目は見つかりませんでした。一覧を更新してください。"
        case .empty: "保存する本文を入力してください。"
        case .tooLarge: "タイトルは512バイト、本文は1 MB以内で保存できます。"
        }
    }
}

enum SnippetText {
    /// Compare the original bytes, including canonically equivalent Unicode.
    /// Contiguous buffers avoid UTF8View's per-byte iteration on long input.
    static func hasSameBytes(_ lhs: String, _ rhs: String) -> Bool {
        var lhs = lhs, rhs = rhs
        return lhs.withUTF8 { left in
            rhs.withUTF8 { right in
                guard left.count == right.count else { return false }
                guard !left.isEmpty else { return true }
                return memcmp(left.baseAddress!, right.baseAddress!, left.count) == 0
            }
        }
    }

    static func searchKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .replacingOccurrences(of: "\0", with: "\u{FFFD}")
    }

    static func validate(title: String, body: String) throws {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.empty }
        guard title.utf8.count <= 512, body.utf8.count <= 1_000_000 else { throw StoreError.tooLarge }
    }
}

enum AppRoute: Equatable {
    case library, create

    init?(url: URL) {
        guard url.scheme == "nibble", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, url.path.isEmpty else { return nil }
        switch url.host {
        case "library": self = .library
        case "new": self = .create
        default: return nil
        }
    }
}
