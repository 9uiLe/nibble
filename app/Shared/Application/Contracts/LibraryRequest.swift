import Foundation

struct LibraryRequest: Equatable, Sendable {
    static let pageSize = 100
    static let draftPreviewLimit = 1
    private let queryBytes: Data
    var query: String { String(decoding: queryBytes, as: UTF8.self) }
    let filter: LibraryFilter
    let limit: Int

    init(query: String = "", filter: LibraryFilter = .all, limit: Int = LibraryRequest.pageSize) {
        self.filter = filter
        queryBytes = Data(query.utf8)
        self.limit = max(1, min(limit, Int.max - 1))
    }

    var includesDrafts: Bool {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return filter == .all || filter == .drafts
    }

    var expanded: LibraryRequest {
        let room = Int.max - Self.pageSize - 1
        return LibraryRequest(query: query, filter: filter, limit: min(limit, room) + Self.pageSize)
    }
}

struct LibraryCounts: Equatable, Sendable {
    var saved = 0
    var pinned = 0
    var drafts = 0

    func count(for filter: LibraryFilter) -> Int? {
        switch filter {
        case .drafts: drafts
        case .pinned: pinned
        case .all: saved
        case .trash: nil
        }
    }
}

struct LibraryPage: Equatable, Sendable {
    let counts: LibraryCounts
    let items: [SnippetSummary]
    let drafts: [DraftSummary]
    let hasMore: Bool
    let hasMoreDrafts: Bool

    init(items: [SnippetSummary] = [], drafts: [DraftSummary] = [], hasMore: Bool = false,
         hasMoreDrafts: Bool = false, counts: LibraryCounts = LibraryCounts()) {
        self.items = items
        self.drafts = drafts
        self.hasMore = hasMore
        self.hasMoreDrafts = hasMoreDrafts
        self.counts = counts
    }
}

protocol LibraryReading: Sendable {
    // One read transaction supplies the ordered batch, including its counts and page boundaries.
    func libraries(_ requests: [LibraryRequest]) async throws -> [LibraryPage]
}

extension LibraryReading {
    func library(_ request: LibraryRequest) async throws -> LibraryPage {
        let batch = try await libraries([request])
        guard batch.count == 1 else { throw StoreError.unavailable }
        return batch[0]
    }
}
