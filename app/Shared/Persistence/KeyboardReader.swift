import Foundation

/// Every operation releases its connection. Reads cannot create or migrate a
/// store, and an allowed pin write can open only the existing file.
actor KeyboardReader: KeyboardReading {
    private let resolveLocation: @Sendable () throws -> URL

    init(location: @escaping @Sendable () throws -> URL = SnippetLocation.database) { resolveLocation = location }

    private func open(writing: Bool = false) throws -> SQLiteDatabase {
        try Task.checkCancellation()
        let location = try resolveLocation()
        guard FileManager.default.fileExists(atPath: location.path) else { throw KeyboardReadError.notPrepared }
        let connection = try SQLiteDatabase(url: location, access: writing ? .readWriteExisting : .readOnly)
        let versions = try connection.rows("PRAGMA user_version", []) { try $0.int(0) }
        guard let version = versions.first, version >= 1 else { throw KeyboardReadError.notPrepared }
        guard version <= 2 else { throw StoreError.newerVersion }
        return connection
    }

    func page(_ request: KeyboardRequest) throws -> KeyboardPage {
        let connection = try open()
        return try connection.readTransaction {
            let rows = try SnippetQueries.search(connection, query: "", filter: request.filter.libraryFilter,
                                                 limit: KeyboardRequest.pageSize + 1, offset: request.offset,
                                                 ordering: .pinnedFirst, includesUsage: false)
            try Task.checkCancellation()
            return KeyboardPage(items: Array(rows.prefix(KeyboardRequest.pageSize)), hasMore: rows.count > KeyboardRequest.pageSize)
        }
    }

    func body(for item: SnippetSummary) throws -> String {
        do {
            let body = try SnippetQueries.savedBody(open(), id: item.id, revision: item.revision)
            try Task.checkCancellation()
            return body
        } catch StoreError.conflict {
            throw KeyboardReadError.changed
        }
    }

    func setPinned(_ pinned: Bool, for item: SnippetSummary) throws -> SnippetSummary {
        let connection = try open(writing: true)
        try connection.preserveWAL()
        do {
            return try connection.writeTransaction {
                try Task.checkCancellation()
                try SnippetCommands.setPinned(pinned, id: item.id, revision: item.revision, in: connection)
                return try SnippetQueries.summary(connection, id: item.id, includesUsage: false)
            }
        } catch StoreError.conflict {
            throw KeyboardReadError.changed
        }
    }
}
