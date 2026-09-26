import Foundation

struct Snippet: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let pinned: Bool
    let revision: Int
    let updatedAt: Date
    let deleted: Bool
    let usage: SnippetUsage
}

struct SnippetSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let pinned: Bool
    let revision: Int
    /// Keyboard projections deliberately do not read usage (including schema 1).
    let usage: SnippetUsage?

    init(id: UUID, title: String, preview: String, pinned: Bool, revision: Int, usage: SnippetUsage? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.pinned = pinned
        self.revision = revision
        self.usage = usage
    }
}

struct SnippetUsage: Equatable, Sendable {
    static let inactivityDays = 30
    static let never = SnippetUsage(state: .never)

    private enum State: Equatable, Sendable {
        case never
        case used(count: Int, lastUsedAt: Date)
    }
    private let state: State

    private init(state: State) { self.state = state }

    init?(count: Int, lastUsedAt: Date?) {
        switch (count, lastUsedAt) {
        case (0, nil): state = .never
        case (1..., .some(let date)) where date.timeIntervalSince1970.isFinite:
            state = .used(count: count, lastUsedAt: date)
        default: return nil
        }
    }

    var count: Int {
        switch state {
        case .never: 0
        case .used(let count, _): count
        }
    }

    var lastUsedAt: Date? {
        switch state {
        case .never: nil
        case .used(_, let date): date
        }
    }

    func isDeletionCandidate(at date: Date) -> Bool {
        switch state {
        case .never: false
        case .used(_, let lastUsedAt):
            date.timeIntervalSince(lastUsedAt) >= Double(Self.inactivityDays * 24 * 60 * 60)
        }
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

    var ordering: SnippetOrdering { self == .trash ? .recentlyUpdated : .mostUsed }
}

/// Each entry chooses an ordering; storage translates it without sorting loaded bodies.
enum SnippetOrdering {
    case mostUsed, recentlyUpdated, pinnedFirst
}
