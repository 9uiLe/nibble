import Foundation

struct LibraryRequest: Equatable, Sendable {
    static let pageSize = 100
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
    var items: [SnippetSummary] = []
    var drafts: [DraftSummary] = []
    var hasMore = false
}

