import Foundation
import SQLite3

/// Each operation owns a short SQLite connection. WAL and revision checks coordinate
/// the app and extensions without keeping a suspended process's transaction open.
actor WorkspaceRepository: WorkspaceStorage {
    private let location: URL
    private let readOnly: Bool
    private static let cardColumns = "id,title,body,version,modified_at,pinned,deleted_at,origin_title,uses_variables"
    private static let draftColumns = "id,target_kind,target_id,base_version,title,body,values_json,sequence,modified_at,uses_variables"

    init(location: URL? = nil, readOnly: Bool = false) throws {
        let resolved: URL
        if let location {
            resolved = location
        } else {
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.nibble.9uiLe.com") else {
                throw WorkspaceError.unavailable
            }
            resolved = container.appendingPathComponent("Library", isDirectory: true).appendingPathComponent("workspace.sqlite")
        }
        self.location = resolved
        self.readOnly = readOnly
        if readOnly {
            let database = try WorkspaceDatabase(url: resolved, readOnly: true)
            try Self.checkSchema(database)
            return
        }
        do {
            try FileManager.default.createDirectory(at: resolved.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
        } catch {
            throw WorkspaceError.unavailable
        }
        let database = try WorkspaceDatabase(url: resolved, readOnly: false, create: true)
        let version = try database.scalar("PRAGMA user_version")
        guard version == 0 || version == 2 else { throw WorkspaceError.unsupportedSchema }
        try database.execute("PRAGMA journal_mode=WAL")
        try database.preserveWAL()
        try database.writeTransaction {
            try database.execute("""
            CREATE TABLE IF NOT EXISTS cards(
                id TEXT PRIMARY KEY NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,
                version INTEGER NOT NULL CHECK(version>0),modified_at REAL NOT NULL,
                pinned INTEGER NOT NULL CHECK(pinned IN(0,1)),deleted_at REAL,origin_title TEXT,
                search_text TEXT NOT NULL,has_variables INTEGER NOT NULL CHECK(has_variables IN(0,1)),
                uses_variables INTEGER NOT NULL DEFAULT 0 CHECK(uses_variables IN(0,1))
            )
            """)
            try database.execute("CREATE INDEX IF NOT EXISTS cards_listing ON cards(deleted_at,pinned DESC,modified_at DESC,id)")
            try database.execute("""
            CREATE TABLE IF NOT EXISTS work_drafts(
                id TEXT PRIMARY KEY NOT NULL,target_kind INTEGER NOT NULL CHECK(target_kind IN(0,1,2)),
                target_id TEXT,base_version INTEGER,title TEXT NOT NULL,body TEXT NOT NULL,
                values_json TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>=0),modified_at REAL NOT NULL,
                uses_variables INTEGER NOT NULL DEFAULT 0 CHECK(uses_variables IN(0,1))
            )
            """)
            try database.execute("PRAGMA user_version=2")
        }
        do {
            for path in [resolved.path, resolved.path + "-wal", resolved.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            }
        } catch { throw WorkspaceError.unavailable }
    }

    func list(query: WorkspaceQuery) throws -> WorkspacePage {
        let database = try reader()
        let limit = min(max(query.limit, 1), 50)
        let offset = max(query.offset, 0)
        let deleted = query.trash ? "deleted_at IS NOT NULL" : "deleted_at IS NULL"
        let condition = "\(deleted) AND (?=0 OR pinned=1) AND (?='' OR instr(search_text,?)>0)"
        let normalized = Self.searchText(query.query)
        let arguments: [WorkspaceSQLValue] = [.integer(query.pinnedOnly ? 1 : 0), .text(normalized), .text(normalized)]
        return try database.readTransaction {
            let total = try database.scalar("SELECT COUNT(*) FROM cards WHERE \(condition)", arguments)
            let cards = try database.rows("""
            SELECT \(Self.cardColumns) FROM cards WHERE \(condition)
            ORDER BY pinned DESC,modified_at DESC,id LIMIT ? OFFSET ?
            """, arguments + [.integer(limit), .integer(offset)], map: Self.decodeCard)
            return WorkspacePage(cards: cards, total: total, hasMore: offset < total - cards.count)
        }
    }

    func card(id: UUID) throws -> TextCard {
        try Self.fetchCard(id, database: reader())
    }

    func drafts() throws -> [WorkDraft] {
        try reader().rows("SELECT \(Self.draftColumns) FROM work_drafts ORDER BY modified_at DESC,id", [], map: Self.decodeDraft)
    }

    func draft(id: UUID) throws -> WorkDraft {
        try Self.fetchDraft(id, database: reader())
    }

    func beginDraft(title: String = "", body: String = "") throws -> WorkDraft {
        let candidate = WorkDraft(title: title, body: body)
        let database = try writer()
        try Self.insertDraft(candidate, database: database)
        return candidate
    }

    func editingDraft(cardID: UUID) throws -> WorkDraft {
        try beginCardDraft(cardID: cardID, preparation: false)
    }

    func preparationDraft(cardID: UUID) throws -> WorkDraft {
        try beginCardDraft(cardID: cardID, preparation: true)
    }

    private func beginCardDraft(cardID: UUID, preparation: Bool) throws -> WorkDraft {
        let database = try writer()
        return try database.writeTransaction {
            let card = try Self.fetchCard(cardID, database: database)
            guard card.deletedAt == nil else { throw WorkspaceError.missingCard }
            let target: WorkDraft.Target = preparation
                ? .prepare(cardID: card.id, baseVersion: card.version)
                : .edit(cardID: card.id, baseVersion: card.version)
            let candidate = WorkDraft(target: target, title: card.title, body: card.body, usesVariables: card.usesVariables)
            try Self.insertDraft(candidate, database: database)
            return candidate
        }
    }

    @discardableResult
    func checkpoint(_ draft: WorkDraft) throws -> WorkDraft {
        let database = try writer()
        return try database.writeTransaction { try Self.checkpoint(draft, database: database) }
    }

    /// Saving work and publishing are separate commits: a rejected publication
    /// retains the exact latest input for recovery.
    func publish(_ draft: WorkDraft) throws -> TextCard {
        _ = try checkpoint(draft)
        let database = try writer()
        return try database.writeTransaction {
            let saved = try Self.fetchDraft(draft.id, database: database)
            guard saved.sequence == draft.sequence, saved.hasSameInput(as: draft) else { throw WorkspaceError.staleCheckpoint }
            let candidate: TextCard
            switch draft.target {
            case .new:
                candidate = TextCard(title: draft.title, body: draft.body, usesVariables: draft.usesVariables)
            case .edit(let cardID, let baseVersion):
                let original = try Self.fetchActiveCard(cardID, expectedVersion: baseVersion, database: database)
                guard original.version < Int.max else { throw WorkspaceError.conflict }
                candidate = TextCard(id: original.id, title: draft.title, body: draft.body, usesVariables: draft.usesVariables, version: original.version + 1,
                                     pinned: original.pinned, originTitle: original.originTitle)
            case .prepare(let cardID, let baseVersion):
                let original = try Self.fetchActiveCard(cardID, expectedVersion: baseVersion, database: database)
                candidate = TextCard(title: draft.title, body: try draft.renderedBody(), originTitle: original.title)
            }
            guard !candidate.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.emptyBody }
            try Self.writeCard(candidate, database: database)
            try database.execute("DELETE FROM work_drafts WHERE id=? AND sequence=?", [.text(draft.id.uuidString), .integer(draft.sequence)])
            guard database.changes == 1 else { throw WorkspaceError.staleCheckpoint }
            return candidate
        }
    }

    func discardDraft(id: UUID, expectedSequence: Int) throws {
        let database = try writer()
        try database.writeTransaction {
            let saved = try Self.fetchDraft(id, database: database)
            guard saved.sequence == expectedSequence else { throw WorkspaceError.staleCheckpoint }
            try database.execute("DELETE FROM work_drafts WHERE id=? AND sequence=?", [.text(id.uuidString), .integer(expectedSequence)])
            guard database.changes == 1 else { throw WorkspaceError.staleCheckpoint }
        }
    }

    @discardableResult
    func setPinned(_ pinned: Bool, cardID: UUID, expectedVersion: Int) throws -> TextCard {
        try mutateCard(cardID: cardID, expectedVersion: expectedVersion, operation: .pin(pinned))
    }

    @discardableResult
    func trash(cardID: UUID, expectedVersion: Int) throws -> TextCard {
        try mutateCard(cardID: cardID, expectedVersion: expectedVersion, operation: .trash)
    }

    @discardableResult
    func restore(cardID: UUID, expectedVersion: Int) throws -> TextCard {
        try mutateCard(cardID: cardID, expectedVersion: expectedVersion, operation: .restore)
    }

    func keyboardSummaries(limit: Int = 50) throws -> [PreparedCardSummary] {
        try reader().rows("""
        SELECT id,substr(title,1,256),substr(body,1,1024),version,modified_at,substr(origin_title,1,256)
        FROM cards WHERE deleted_at IS NULL AND pinned=1 AND has_variables=0
        ORDER BY modified_at DESC,id LIMIT ?
        """, [.integer(min(max(limit, 1), 50))]) { row in
            try PreparedCardSummary(id: row.uuid(0), title: row.text(1), preview: String(row.text(2).prefix(180)),
                                    version: row.integer(3), modifiedAt: Date(timeIntervalSince1970: row.real(4)),
                                    originTitle: row.isNull(5) ? nil : row.text(5))
        }
    }

    func revalidate(cardID: UUID, expectedVersion: Int) throws -> TextCard {
        try Self.fetchActiveCard(cardID, expectedVersion: expectedVersion, database: reader())
    }

    private enum CardMutation { case pin(Bool), trash, restore }

    private func mutateCard(cardID: UUID, expectedVersion: Int, operation: CardMutation) throws -> TextCard {
        let database = try writer()
        return try database.writeTransaction {
            let original = try Self.fetchCard(cardID, database: database)
            guard original.version == expectedVersion, original.version < Int.max else { throw WorkspaceError.conflict }
            var pinned = original.pinned
            var deletedAt = original.deletedAt
            switch operation {
            case .pin(let value):
                guard original.deletedAt == nil else { throw WorkspaceError.missingCard }
                if value == pinned { return original }
                pinned = value
            case .trash:
                guard original.deletedAt == nil else { throw WorkspaceError.missingCard }
                deletedAt = Date()
            case .restore:
                guard original.deletedAt != nil else { throw WorkspaceError.missingCard }
                deletedAt = nil
            }
            let result = TextCard(id: original.id, title: original.title, body: original.body, usesVariables: original.usesVariables, version: original.version + 1,
                                  pinned: pinned, deletedAt: deletedAt, originTitle: original.originTitle)
            try Self.writeCard(result, database: database)
            return result
        }
    }

    private func reader() throws -> WorkspaceDatabase {
        let database = try WorkspaceDatabase(url: location, readOnly: true)
        try Self.checkSchema(database)
        return database
    }

    private func writer() throws -> WorkspaceDatabase {
        guard !readOnly else { throw WorkspaceError.readOnly }
        let database = try WorkspaceDatabase(url: location, readOnly: false)
        try Self.checkSchema(database)
        try database.preserveWAL()
        return database
    }

    private static func checkSchema(_ database: WorkspaceDatabase) throws {
        guard try database.scalar("PRAGMA user_version") == 2 else { throw WorkspaceError.unsupportedSchema }
    }

    private static func fetchCard(_ id: UUID, database: WorkspaceDatabase) throws -> TextCard {
        guard let found = try database.rows("SELECT \(cardColumns) FROM cards WHERE id=?", [.text(id.uuidString)], map: decodeCard).first else {
            throw WorkspaceError.missingCard
        }
        return found
    }

    private static func fetchActiveCard(_ id: UUID, expectedVersion: Int, database: WorkspaceDatabase) throws -> TextCard {
        let found = try fetchCard(id, database: database)
        guard found.deletedAt == nil else { throw WorkspaceError.missingCard }
        guard found.version == expectedVersion else { throw WorkspaceError.conflict }
        return found
    }

    private static func fetchDraft(_ id: UUID, database: WorkspaceDatabase) throws -> WorkDraft {
        guard let found = try database.rows("SELECT \(draftColumns) FROM work_drafts WHERE id=?", [.text(id.uuidString)], map: decodeDraft).first else {
            throw WorkspaceError.missingDraft
        }
        return found
    }

    private static func checkpoint(_ draft: WorkDraft, database: WorkspaceDatabase) throws -> WorkDraft {
        guard draft.sequence >= 0, draft.sequence < Int.max else { throw WorkspaceError.invalidDraft }
        let previous = try fetchDraft(draft.id, database: database)
        guard draft.target == previous.target, draft.sequence >= previous.sequence else { throw WorkspaceError.staleCheckpoint }
        if draft.sequence == previous.sequence {
            guard draft.hasSameInput(as: previous) else { throw WorkspaceError.staleCheckpoint }
            return previous
        }
        guard draft.checkpointSequence == previous.sequence else { throw WorkspaceError.staleCheckpoint }
        let result = WorkDraft(id: draft.id, target: draft.target, title: draft.title, body: draft.body, usesVariables: draft.usesVariables,
                               values: draft.values, sequence: draft.sequence)
        try database.execute("""
        UPDATE work_drafts SET title=?,body=?,values_json=?,sequence=?,modified_at=?,uses_variables=? WHERE id=? AND sequence=?
        """, [.text(result.title), .text(result.body), .text(try encodeValues(result.values)), .integer(result.sequence),
              .real(result.modifiedAt.timeIntervalSince1970), .integer(result.usesVariables ? 1 : 0),
              .text(result.id.uuidString), .integer(previous.sequence)])
        guard database.changes == 1 else { throw WorkspaceError.staleCheckpoint }
        return result
    }

    private static func insertDraft(_ draft: WorkDraft, database: WorkspaceDatabase) throws {
        let kind: Int
        switch draft.target {
        case .new: kind = 0
        case .edit: kind = 1
        case .prepare: kind = 2
        }
        try database.execute("""
        INSERT INTO work_drafts(\(draftColumns)) VALUES(?,?,?,?,?,?,?,?,?,?)
        """, [.text(draft.id.uuidString), .integer(kind), draft.cardID.map { .text($0.uuidString) } ?? .null,
              draft.baseVersion.map { .integer($0) } ?? .null, .text(draft.title), .text(draft.body),
              .text(try encodeValues(draft.values)), .integer(draft.sequence), .real(draft.modifiedAt.timeIntervalSince1970),
              .integer(draft.usesVariables ? 1 : 0)])
    }

    private static func writeCard(_ card: TextCard, database: WorkspaceDatabase) throws {
        try database.execute("""
        INSERT INTO cards(\(cardColumns),search_text,has_variables) VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,version=excluded.version,
            modified_at=excluded.modified_at,pinned=excluded.pinned,deleted_at=excluded.deleted_at,
            origin_title=excluded.origin_title,uses_variables=excluded.uses_variables,
            search_text=excluded.search_text,has_variables=excluded.has_variables
        """, [.text(card.id.uuidString), .text(card.title), .text(card.body), .integer(card.version),
              .real(card.modifiedAt.timeIntervalSince1970), .integer(card.pinned ? 1 : 0),
              card.deletedAt.map { .real($0.timeIntervalSince1970) } ?? .null, card.originTitle.map { .text($0) } ?? .null,
              .integer(card.usesVariables ? 1 : 0), .text(searchText(card.title + "\n" + card.body)),
              .integer(card.usesVariables && !TextTemplate(card.body).names.isEmpty ? 1 : 0)])
    }

    private static func decodeCard(_ row: WorkspaceSQLRow) throws -> TextCard {
        let version = try row.integer(3)
        guard version > 0 else { throw WorkspaceError.corruptData }
        return try TextCard(id: row.uuid(0), title: row.text(1), body: row.text(2), usesVariables: row.boolean(8), version: version,
                            modifiedAt: Date(timeIntervalSince1970: row.real(4)), pinned: row.boolean(5),
                            deletedAt: row.isNull(6) ? nil : Date(timeIntervalSince1970: row.real(6)),
                            originTitle: row.isNull(7) ? nil : row.text(7))
    }

    private static func decodeDraft(_ row: WorkspaceSQLRow) throws -> WorkDraft {
        let target: WorkDraft.Target
        let kind = try row.integer(1)
        switch kind {
        case 0:
            guard row.isNull(2), row.isNull(3) else { throw WorkspaceError.corruptData }
            target = .new
        case 1, 2:
            let id = try row.uuid(2)
            let version = try row.integer(3)
            guard version > 0 else { throw WorkspaceError.corruptData }
            target = kind == 1 ? .edit(cardID: id, baseVersion: version) : .prepare(cardID: id, baseVersion: version)
        default: throw WorkspaceError.corruptData
        }
        let sequence = try row.integer(7)
        guard sequence >= 0, sequence < Int.max else { throw WorkspaceError.corruptData }
        let encoded = try row.text(6)
        let values: [String: String]
        do {
            values = try JSONDecoder().decode([String: String].self, from: Data(encoded.utf8))
        } catch {
            throw WorkspaceError.corruptData
        }
        return try WorkDraft(id: row.uuid(0), target: target, title: row.text(4), body: row.text(5), usesVariables: row.boolean(9), values: values,
                             sequence: sequence, modifiedAt: Date(timeIntervalSince1970: row.real(8)))
    }

    private static func encodeValues(_ values: [String: String]) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(values), as: UTF8.self)
        } catch {
            throw WorkspaceError.invalidDraft
        }
    }

    private static func searchText(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

private enum WorkspaceSQLValue {
    case text(String)
    case integer(Int)
    case real(Double)
    case null
}

private final class WorkspaceDatabase {
    private let handle: OpaquePointer
    var changes: Int { Int(sqlite3_changes(handle)) }

    init(url: URL, readOnly: Bool, create: Bool = false) throws {
        var candidate: OpaquePointer?
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &candidate, access | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let candidate else {
            sqlite3_close_v2(candidate)
            throw WorkspaceError.storage(code: status)
        }
        handle = candidate
        let timeout = sqlite3_busy_timeout(candidate, 2_000)
        guard timeout == SQLITE_OK else {
            sqlite3_close_v2(candidate)
            throw WorkspaceError.storage(code: timeout)
        }
    }

    deinit { sqlite3_close_v2(handle) }

    func preserveWAL() throws {
        var persist: Int32 = 1
        let status = sqlite3_file_control(handle, "main", SQLITE_FCNTL_PERSIST_WAL, &persist)
        guard status == SQLITE_OK else { throw WorkspaceError.storage(code: status) }
    }

    func readTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try performTransaction(writing: false, operation)
    }

    func writeTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try performTransaction(writing: true, operation)
    }

    private func performTransaction<Result>(writing: Bool, _ operation: () throws -> Result) throws -> Result {
        try execute(writing ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            let failure = error
            try execute("ROLLBACK")
            throw failure
        }
    }

    func execute(_ sql: String, _ arguments: [WorkspaceSQLValue] = []) throws {
        _ = try rows(sql, arguments) { _ in true }
    }

    func scalar(_ sql: String, _ arguments: [WorkspaceSQLValue] = []) throws -> Int {
        guard let number = try rows(sql, arguments, map: { try $0.integer(0) }).first else { throw WorkspaceError.corruptData }
        return number
    }

    func rows<Result>(_ sql: String, _ arguments: [WorkspaceSQLValue], map: (WorkspaceSQLRow) throws -> Result) throws -> [Result] {
        var prepared: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
        guard status == SQLITE_OK, let statement = prepared else {
            sqlite3_finalize(prepared)
            throw WorkspaceError.storage(code: status)
        }
        defer { sqlite3_finalize(statement) }
        guard Int(sqlite3_bind_parameter_count(statement)) == arguments.count else { throw WorkspaceError.corruptData }
        for (index, argument) in arguments.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch argument {
            case .null: status = sqlite3_bind_null(statement, position)
            case .integer(let value): status = sqlite3_bind_int64(statement, position, Int64(value))
            case .real(let value): status = sqlite3_bind_double(statement, position, value)
            case .text(let value):
                guard value.utf8.count <= Int(Int32.max) else { throw WorkspaceError.invalidDraft }
                status = value.utf8CString.withUnsafeBufferPointer { buffer in
                    sqlite3_bind_text(statement, position, buffer.baseAddress, Int32(buffer.count - 1),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard status == SQLITE_OK else { throw WorkspaceError.storage(code: status) }
        }
        var result: [Result] = []
        while true {
            let step = sqlite3_step(statement)
            switch step {
            case SQLITE_ROW: result.append(try map(WorkspaceSQLRow(statement: statement)))
            case SQLITE_DONE: return result
            default: throw WorkspaceError.storage(code: step)
            }
        }
    }
}

private struct WorkspaceSQLRow {
    let statement: OpaquePointer

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

    func text(_ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT else { throw WorkspaceError.corruptData }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0 else { return "" }
        guard let pointer = sqlite3_column_text(statement, column),
              let result = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8) else {
            throw WorkspaceError.corruptData
        }
        return result
    }

    func integer(_ column: Int32) throws -> Int {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER,
              let result = Int(exactly: sqlite3_column_int64(statement, column)) else { throw WorkspaceError.corruptData }
        return result
    }

    func boolean(_ column: Int32) throws -> Bool {
        switch try integer(column) {
        case 0: false
        case 1: true
        default: throw WorkspaceError.corruptData
        }
    }

    func uuid(_ column: Int32) throws -> UUID {
        guard let result = UUID(uuidString: try text(column)) else { throw WorkspaceError.corruptData }
        return result
    }

    func real(_ column: Int32) throws -> Double {
        let kind = sqlite3_column_type(statement, column)
        guard kind == SQLITE_INTEGER || kind == SQLITE_FLOAT else { throw WorkspaceError.corruptData }
        let result = sqlite3_column_double(statement, column)
        guard result.isFinite else { throw WorkspaceError.corruptData }
        return result
    }
}
