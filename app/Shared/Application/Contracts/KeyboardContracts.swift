import Foundation

enum KeyboardFilter: String, CaseIterable, Sendable {
    case all
    case pinned

    var libraryFilter: LibraryFilter {
        switch self {
        case .all: .all
        case .pinned: .pinned
        }
    }
}

struct KeyboardRequest: Hashable, Sendable {
    static let pageSize = 50
    let filter: KeyboardFilter
    let offset: Int

    init(filter: KeyboardFilter = .all, offset: Int = 0) {
        self.filter = filter
        self.offset = max(0, min(offset, Int.max - Self.pageSize - 1))
    }
}

struct KeyboardPage: Equatable, Sendable {
    let items: [SnippetSummary]
    let hasMore: Bool
}

protocol KeyboardReading: Sendable {
    func body(for item: SnippetSummary) async throws -> String
    func page(_ request: KeyboardRequest) async throws -> KeyboardPage
    func setPinned(_ pinned: Bool, for item: SnippetSummary) async throws -> SnippetSummary
}

enum KeyboardReadError: Error, Equatable {
    case notPrepared
    case changed
}
