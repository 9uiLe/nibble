import Foundation

/// All pages and counts are read in one database transaction, in request order.
/// Implementations must not compose independent reads into a batch.
protocol LibraryReading: Sendable {
    func libraries(_ requests: [LibraryRequest]) async throws -> [LibraryPage]
}

extension LibraryReading {
    func library(_ request: LibraryRequest) async throws -> LibraryPage {
        let pages = try await libraries([request])
        guard pages.count == 1, let page = pages.first else { throw StoreError.unavailable }
        return page
    }
}

struct LibraryRequest: Equatable, Sendable {
    static let pageSize = 100
    static let draftPreviewLimit = 1
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

/// Collection totals are independent of the current search and pagination limit.
struct LibraryCounts: Equatable, Sendable {
    var saved = 0
    var pinned = 0
    var drafts = 0

    func count(for filter: LibraryFilter) -> Int? {
        switch filter {
        case .all: saved
        case .pinned: pinned
        case .drafts: drafts
        case .trash: nil
        }
    }
}

/// Snippet rows, draft rows and pagination all describe the same database read snapshot.
struct LibraryPage: Equatable, Sendable {
    let counts: LibraryCounts
    let items: [SnippetSummary]
    let drafts: [DraftSummary]
    let hasMore: Bool
    let hasMoreDrafts: Bool

    init(items: [SnippetSummary] = [], drafts: [DraftSummary] = [], hasMore: Bool = false, hasMoreDrafts: Bool = false,
         counts: LibraryCounts = LibraryCounts()) {
        self.counts = counts
        self.items = items
        self.drafts = drafts
        self.hasMore = hasMore
        self.hasMoreDrafts = hasMoreDrafts
    }
}
