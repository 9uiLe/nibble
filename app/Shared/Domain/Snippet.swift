import Foundation

struct Snippet: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let pinned: Bool
    let revision: Int
    let updatedAt: Date
    let deleted: Bool
    let usage: SnippetUsage
}

struct SnippetSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let pinned: Bool
    let revision: Int
    let usage: SnippetUsage?

    init(id: UUID, title: String, preview: String, pinned: Bool, revision: Int, usage: SnippetUsage? = nil) {
        (self.id, self.title, self.preview) = (id, title, preview)
        (self.pinned, self.revision, self.usage) = (pinned, revision, usage)
    }
}

/// Construction validates the count/date pair. Optional projections distinguish
/// unobserved usage from a measured count of zero.
struct SnippetUsage: Equatable, Sendable {
    static let inactivityDays = 30
    static let never = SnippetUsage()
    let count: Int
    let lastUsedAt: Date?

    private init() {
        count = 0
        lastUsedAt = nil
    }

    init?(count: Int, lastUsedAt: Date?) {
        guard count >= 0 else { return nil }
        switch (count, lastUsedAt) {
        case (0, nil): break
        case (1..., .some(let date)):
            guard date.timeIntervalSince1970.isFinite else { return nil }
        default: return nil
        }
        self.count = count
        self.lastUsedAt = lastUsedAt
    }

    func isDeletionCandidate(at date: Date) -> Bool {
        guard let lastUsedAt else { return false }
        return date.timeIntervalSince(lastUsedAt) >= TimeInterval(Self.inactivityDays) * 86_400
    }
}

struct SnippetUse: Equatable, Sendable {
    let id: UUID
    let snippetID: UUID
    let completedAt: Date
}

enum LibraryFilter: String, CaseIterable, Sendable {
    case all
    case pinned
    case drafts
    case trash

    var ordering: SnippetOrdering {
        switch self {
        case .trash: .recentlyUpdated
        case .all, .pinned, .drafts: .mostUsed
        }
    }
}

enum SnippetOrdering {
    case mostUsed
    case recentlyUpdated
    case pinnedFirst
}
