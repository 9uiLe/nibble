import Foundation

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
        guard let version = try db.rows("PRAGMA user_version", [], map: { try $0.int(0) }).first else {
            throw StoreError.database
        }
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
            do { try SnippetCommands.setPinned(pinned, id: item.id, revision: item.revision, in: db) }
            catch StoreError.conflict { throw KeyboardReadError.changed }
            return try SnippetQueries.summary(db, id: item.id, includesUsage: false)
        }
    }

    func page(_ request: KeyboardRequest) throws -> KeyboardPage {
        let db = try database()
        return try db.readTransaction {
            let items = try SnippetQueries.search(db, query: "", filter: request.filter.libraryFilter,
                limit: KeyboardRequest.pageSize + 1, offset: request.offset, ordering: .pinnedFirst, includesUsage: false)
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
