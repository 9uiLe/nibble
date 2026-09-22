import Foundation

enum KeyboardFilter: String, CaseIterable, Sendable {
    case all, pinned
    var libraryFilter: LibraryFilter { self == .all ? .all : .pinned }
}

struct KeyboardRequest: Hashable, Sendable {
    static let pageSize = 50
    let filter: KeyboardFilter
    let offset: Int

    init(filter: KeyboardFilter = .all, offset: Int = 0) {
        self.filter = filter
        self.offset = min(max(0, offset), Int.max - Self.pageSize - 1)
    }
}

struct KeyboardPage: Equatable, Sendable {
    let items: [SnippetSummary]
    let hasMore: Bool
}

protocol KeyboardReading: Sendable {
    func page(_ request: KeyboardRequest) async throws -> KeyboardPage
    func body(for item: SnippetSummary) async throws -> String
    func setPinned(_ pinned: Bool, for item: SnippetSummary) async throws -> SnippetSummary
}

enum KeyboardReadError: Error, Equatable {
    case notPrepared, changed
}
