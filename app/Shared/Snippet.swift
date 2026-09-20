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
    var useCount = 0
    var lastUsedAt: Date?

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
    var useCount = 0
    var lastUsedAt: Date?
    var displayTitle: String { Snippet.displayTitle(title: title, body: preview) }

    func isDeletionCandidate(at date: Date) -> Bool {
        guard let lastUsedAt else { return false }
        return date.timeIntervalSince(lastUsedAt) >= 30 * 24 * 60 * 60
    }
}

/// One completed copy, with a stable identity for retrying only its usage record.
struct SnippetUse: Equatable, Sendable {
    let id: UUID
    let snippetID: UUID
    let completedAt: Date
}

enum LibraryFilter: String, CaseIterable, Sendable {
    case all, pinned, drafts, trash
    var title: String {
        switch self {
        case .all: "すべて"
        case .pinned: "ピン留め"
        case .drafts: "下書き"
        case .trash: "削除した項目"
        }
    }
}

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
