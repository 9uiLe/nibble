import Foundation

enum KeyboardFilter: String, CaseIterable, Sendable {
    case all, pinned
    var title: String { self == .all ? "すべて" : "ピン留め" }
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

enum KeyboardReadError: Error, LocalizedError {
    case notPrepared, changed

    var errorDescription: String? {
        switch self {
        case .notPrepared: "nibbleでスニペットを保存してから、更新してください。"
        case .changed: "項目が変更されています。一覧を更新して選び直してください。"
        }
    }
}

/// Reads stay read-only. Pinning opens an existing database without preparing or migrating it.
actor KeyboardReader: KeyboardReading {
    private let location: @Sendable () throws -> URL

    init(location: @escaping @Sendable () throws -> URL = SnippetLocation.database) {
        self.location = location
    }

    private func database(access: SQLiteDatabase.Access = .readOnly) throws -> SQLiteDatabase {
        try Task.checkCancellation()
        let url = try location()
        guard FileManager.default.fileExists(atPath: url.path) else { throw KeyboardReadError.notPrepared }
        let db = try SQLiteDatabase(url: url, access: access)
        let version = try db.rows("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
        guard version <= 2 else { throw StoreError.newerVersion }
        guard version >= 1 else { throw KeyboardReadError.notPrepared }
        return db
    }

    func setPinned(_ pinned: Bool, for item: SnippetSummary) throws -> SnippetSummary {
        let db = try database(access: .readWriteExisting)
        // Retain the shared WAL for readers that have no write permission.
        try db.preserveWAL()
        return try db.writeTransaction {
            try Task.checkCancellation()
            try db.execute("UPDATE snippets SET pinned=?,revision=revision+1 WHERE id=? AND revision=? AND deleted=0",
                [.int(pinned ? 1 : 0), .text(item.id.uuidString), .int(item.revision)])
            guard db.changes == 1 else { throw KeyboardReadError.changed }
            return try SnippetQueries.summary(db, id: item.id, includesUsage: false)
        }
    }

    func page(_ request: KeyboardRequest) throws -> KeyboardPage {
        let db = try database()
        return try db.readTransaction {
            let items = try SnippetQueries.search(db, query: "", filter: request.filter == .all ? .all : .pinned,
                limit: KeyboardRequest.pageSize + 1, offset: request.offset, keyboard: true)
            try Task.checkCancellation()
            return KeyboardPage(items: Array(items.prefix(KeyboardRequest.pageSize)), hasMore: items.count > KeyboardRequest.pageSize)
        }
    }

    func body(for item: SnippetSummary) throws -> String {
        let db = try database()
        let value: String
        do { value = try SnippetQueries.savedBody(db, id: item.id, revision: item.revision) }
        catch StoreError.conflict { throw KeyboardReadError.changed }
        try Task.checkCancellation()
        return value
    }
}
