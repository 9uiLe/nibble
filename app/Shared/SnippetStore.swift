import Foundation
import SQLite3
import OSLog

/// All connections and prepared statements stay on this actor. Transactions never suspend.
actor SnippetStore {
    static let groupID = "group.dev.nibble.app"
    static let shared = SnippetStore()
    private let location: URL?
    private var connection: Database?
    private let signposter = OSSignposter(subsystem: "dev.nibble.app", category: "Store")

    init(location: URL? = nil) { self.location = location }

    private func database() throws -> Database {
        if let connection { return connection }
        let url: URL
        if let location {
            url = location
        } else {
            guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) else {
                throw StoreError.unavailable
            }
            url = group.appending(path: "Library/snippets.sqlite")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        let db = try Database(url: url)
        try db.prepare(at: url)
        connection = db
        return db
    }

    func library(_ request: LibraryRequest) throws -> LibraryPage {
        try Task.checkCancellation()
        let db = try database()
        return try db.readTransaction {
            let values = try search(request.query, filter: request.filter, limit: request.limit + 1)
            return LibraryPage(items: Array(values.prefix(request.limit)), drafts: try drafts(),
                               hasMore: values.count > request.limit)
        }
    }

    func search(_ query: String = "", filter: LibraryFilter = .all, limit: Int = 100) throws -> [SnippetSummary] {
        let interval = signposter.beginInterval("Search")
        defer { signposter.endInterval("Search", interval) }
        try Task.checkCancellation()
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        // instr treats %, _ and backslash literally and supports one-character Japanese queries.
        let db = try database()
        return try db.rows("""
            SELECT id,title,substr(body,1,180),pinned,revision FROM snippets
            WHERE deleted=? AND (?=0 OR pinned=1) AND (?='' OR instr(search_key,?)>0)
            ORDER BY pinned DESC,updated DESC,id ASC LIMIT ?
            """, [.int(filter == .trash ? 1 : 0), .int(filter == .pinned ? 1 : 0), .text(key), .text(key), .int(max(1, limit))]) { row in
            return SnippetSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2), pinned: row.int(3) == 1, revision: row.int(4))
        }
    }

    func snippet(_ id: UUID) throws -> Snippet {
        let values = try database().rows("SELECT id,title,body,pinned,revision,updated,deleted FROM snippets WHERE id=?", [.text(id.uuidString)]) { row in
            Snippet(id: id, title: row.text(1), body: row.text(2), pinned: row.int(3) == 1,
                    revision: row.int(4), updatedAt: Date(timeIntervalSince1970: row.double(5)), deleted: row.int(6) == 1)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    /// Creates a distinct editing session. The library uses editingDraft(for:) to resume one.
    func beginDraft(snippetID: UUID? = nil, body: String = "") throws -> Draft {
        let db = try database()
        return try db.writeTransaction { try insertDraft(snippetID: snippetID, body: body, into: db) }
    }

    /// Lookup and creation share one write transaction, even across app/extension connections.
    func editingDraft(for snippetID: UUID) throws -> Draft {
        let db = try database()
        return try db.writeTransaction {
            guard try !snippet(snippetID).deleted else { throw StoreError.missing }
            let existing = try db.rows("SELECT id FROM drafts WHERE snippet_id=? ORDER BY updated DESC,id LIMIT 1",
                                       [.text(snippetID.uuidString)]) { try $0.uuid(0) }
            if let id = existing.first { return try draft(id) }
            return try insertDraft(snippetID: snippetID, body: "", into: db)
        }
    }

    private func insertDraft(snippetID: UUID?, body: String, into db: Database) throws -> Draft {
        let snippet = try snippetID.map { try self.snippet($0) }
        guard snippet?.deleted != true else { throw StoreError.missing }
        let draft = Draft(id: UUID(), snippetID: snippetID, baseRevision: snippet?.revision ?? 0,
                          title: snippet?.title ?? "", body: snippet?.body ?? body)
        try db.execute("INSERT INTO drafts(id,snippet_id,base_revision,title,body,sequence,updated) VALUES(?,?,?,?,?,0,?)",
            [.text(draft.id.uuidString), .text(snippetID?.uuidString ?? ""), .int(draft.baseRevision),
             .text(draft.title), .text(draft.body), .real(Date().timeIntervalSince1970)])
        return draft
    }

    func drafts() throws -> [DraftSummary] {
        try database().rows("SELECT id,substr(title,1,180) FROM drafts ORDER BY updated DESC,id", []) { row in
            DraftSummary(id: try row.uuid(0), title: row.text(1))
        }
    }

    func draft(_ id: UUID) throws -> Draft {
        let values = try database().rows("SELECT snippet_id,base_revision,title,body,sequence FROM drafts WHERE id=?",
                                         [.text(id.uuidString)]) { row in
            let target = row.text(0)
            return Draft(id: id, snippetID: target.isEmpty ? nil : try row.uuid(0), baseRevision: row.int(1),
                         title: row.text(2), body: row.text(3), sequence: row.int(4))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    func updateDraft(_ draft: Draft) throws {
        // UPDATE only: a late queued write cannot resurrect a saved/discarded draft.
        try database().execute("UPDATE drafts SET title=?,body=?,sequence=?,updated=? WHERE id=? AND sequence<?",
            [.text(draft.title), .text(draft.body), .int(draft.sequence), .real(Date().timeIntervalSince1970),
             .text(draft.id.uuidString), .int(draft.sequence)])
    }

    func keepDraft(_ snapshot: Draft) throws {
        let db = try database()
        try db.writeTransaction {
            guard try snapshot.canReplace(draft(snapshot.id)) else { throw StoreError.staleDraft }
            if snapshot.isDisposable { try removeDraft(snapshot.id, from: db) }
            else { try updateDraft(snapshot) }
        }
    }

    func discardDraft(_ snapshot: Draft) throws {
        let db = try database()
        try db.writeTransaction {
            guard try snapshot.canReplace(draft(snapshot.id)) else { throw StoreError.staleDraft }
            try removeDraft(snapshot.id, from: db)
        }
    }

    private func removeDraft(_ id: UUID, from db: Database) throws {
        try db.execute("DELETE FROM drafts WHERE id=?", [.text(id.uuidString)])
    }

    @discardableResult
    func save(_ draft: Draft, asNew: Bool = false) throws -> UUID {
        let interval = signposter.beginInterval("Save")
        defer { signposter.endInterval("Save", interval) }
        try SnippetText.validate(title: draft.title, body: draft.body)
        let db = try database()
        let id = asNew ? UUID() : (draft.snippetID ?? UUID())
        let key = SnippetText.searchKey(draft.title + "\n" + draft.body)
        try db.writeTransaction {
            let replacesDraft: Bool
            do { replacesDraft = try draft.canReplace(self.draft(draft.id)) }
            catch StoreError.missing where asNew { replacesDraft = false }
            guard asNew || replacesDraft else { throw StoreError.staleDraft }
            if draft.snippetID != nil && !asNew {
                try db.execute("UPDATE snippets SET title=?,body=?,search_key=?,updated=?,revision=revision+1 WHERE id=? AND revision=? AND deleted=0",
                    [.text(draft.title), .text(draft.body), .text(key), .real(Date().timeIntervalSince1970), .text(id.uuidString), .int(draft.baseRevision)])
                guard db.changes == 1 else { throw StoreError.conflict }
            } else {
                try db.execute("INSERT INTO snippets(id,title,body,search_key,pinned,revision,updated,deleted) VALUES(?,?,?,?,0,1,?,0)",
                    [.text(id.uuidString), .text(draft.title), .text(draft.body), .text(key), .real(Date().timeIntervalSince1970)])
            }
            // A conflict copy must not remove another editor's newer input.
            if replacesDraft { try removeDraft(draft.id, from: db) }
        }
        return id
    }

    func setPinned(_ pinned: Bool, id: UUID) throws {
        let db = try database()
        try db.execute("UPDATE snippets SET pinned=?,revision=revision+1 WHERE id=? AND deleted=0", [.int(pinned ? 1 : 0), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
    }

    func setDeleted(_ deleted: Bool, id: UUID) throws {
        let db = try database()
        try db.execute("UPDATE snippets SET deleted=?,updated=?,revision=revision+1 WHERE id=?",
            [.int(deleted ? 1 : 0), .real(Date().timeIntervalSince1970), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
    }

    func permanentlyDelete(_ id: UUID) throws {
        let db = try database()
        try db.writeTransaction {
            try db.execute("DELETE FROM snippets WHERE id=? AND deleted=1", [.text(id.uuidString)])
            guard db.changes == 1 else { throw StoreError.missing }
            try db.execute("DELETE FROM drafts WHERE snippet_id=?", [.text(id.uuidString)])
        }
    }
}

private enum SQLValue {
    case text(String), int(Int), real(Double)
}

/// Non-Sendable handle owner, used only inside SnippetStore; no pointer escapes.
private final class Database {
    private let handle: OpaquePointer
    var changes: Int { Int(sqlite3_changes(handle)) }

    init(url: URL) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw StoreError.database
        }
        handle = opened
    }

    func prepare(at url: URL) throws {
        sqlite3_busy_timeout(handle, 2_000)
        let version = try rows("PRAGMA user_version", []) { $0.int(0) }.first ?? 0
        guard version <= 1 else { throw StoreError.newerVersion }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        if version == 0 {
            try writeTransaction {
                try execute("CREATE TABLE IF NOT EXISTS snippets(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL)")
                try execute("CREATE INDEX IF NOT EXISTS snippets_order ON snippets(deleted,pinned DESC,updated DESC,id)")
                try execute("CREATE TABLE IF NOT EXISTS drafts(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)")
                try execute("PRAGMA user_version=1")
            }
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    deinit { sqlite3_close_v2(handle) }

    func readTransaction<T>(_ work: () throws -> T) throws -> T {
        try performTransaction("BEGIN", work)
    }

    func writeTransaction<T>(_ work: () throws -> T) throws -> T {
        try performTransaction("BEGIN IMMEDIATE", work)
    }

    private func performTransaction<T>(_ begin: String, _ work: () throws -> T) throws -> T {
        try execute(begin)
        do {
            let result = try work()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        _ = try rows(sql, values) { _ in true }
    }

    func rows<T>(_ sql: String, _ values: [SQLValue], map: (Row) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreError.database }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = text.utf8CString.withUnsafeBufferPointer {
                    sqlite3_bind_text(statement, index, $0.baseAddress, Int32($0.count - 1), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .int(let number): result = sqlite3_bind_int64(statement, index, Int64(number))
            case .real(let number): result = sqlite3_bind_double(statement, index, number)
            }
            guard result == SQLITE_OK else { throw StoreError.database }
        }
        var output: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw StoreError.database }
            output.append(try map(Row(statement: statement)))
        }
    }
}

private struct Row {
    let statement: OpaquePointer
    func uuid(_ column: Int32) throws -> UUID {
        guard let value = UUID(uuidString: text(column)) else { throw StoreError.database }
        return value
    }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
}
