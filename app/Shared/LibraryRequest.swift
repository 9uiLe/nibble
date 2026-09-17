import Foundation

/// A read completes with one request's database snapshot; it never starts background work.
protocol LibraryReading: Sendable {
    func library(_ request: LibraryRequest) async throws -> LibraryPage
}

struct LibraryRequest: Equatable, Sendable {
    static let pageSize = 100
    static let draftPreviewLimit = 3
    let query: String
    let filter: LibraryFilter
    let limit: Int

    init(query: String = "", filter: LibraryFilter = .all, limit: Int = LibraryRequest.pageSize) {
        self.query = query
        self.filter = filter
        self.limit = min(max(1, limit), Int.max - 1)
    }

    var expanded: Self {
        Self(query: query, filter: filter, limit: min(limit, Int.max - Self.pageSize - 1) + Self.pageSize)
    }
}

/// Snippet rows, draft rows and pagination all describe the same database read snapshot.
struct LibraryPage: Equatable, Sendable {
    let items: [SnippetSummary]
    let drafts: [DraftSummary]
    let hasMore: Bool
    let hasMoreDrafts: Bool
    let pinnedItems: [SnippetSummary]
    let otherItems: [SnippetSummary]

    init(items: [SnippetSummary] = [], drafts: [DraftSummary] = [], hasMore: Bool = false, hasMoreDrafts: Bool = false) {
        self.items = items
        self.drafts = drafts
        self.hasMore = hasMore
        self.hasMoreDrafts = hasMoreDrafts
        var pinned: [SnippetSummary] = []
        var others: [SnippetSummary] = []
        for item in items {
            if item.pinned { pinned.append(item) }
            else { others.append(item) }
        }
        pinnedItems = pinned
        otherItems = others
    }
}

