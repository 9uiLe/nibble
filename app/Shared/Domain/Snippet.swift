import Foundation

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
