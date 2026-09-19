import Foundation

/// Saved-text queries shared by writable stores and the keyboard's read-only connection.
enum SnippetQueries {
    static func requireSaved(_ db: SQLiteDatabase, id: UUID) throws {
        let deleted = try db.rows("SELECT deleted FROM snippets WHERE id=?", [.text(id.uuidString)]) { $0.int(0) }
        guard deleted.first == 0 else { throw StoreError.missing }
    }

    static func summary(_ db: SQLiteDatabase, id: UUID, includesUsage: Bool = true) throws -> SnippetSummary {
        let usage = includesUsage ? "use_count,last_used" : "0,NULL"
        let values = try db.rows("SELECT id,title,substr(body,1,180),pinned,revision,\(usage) FROM snippets WHERE id=?",
                                [.text(id.uuidString)], map: summaryRow)
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    /// Read only the body. Validate the row before allocating its full text in Swift.
    static func savedBody(_ db: SQLiteDatabase, id: UUID, revision: Int? = nil) throws -> String {
        let values = try db.rows("SELECT deleted,revision,body FROM snippets WHERE id=?", [.text(id.uuidString)]) { row in
            guard row.int(0) == 0 else { throw StoreError.missing }
            if let revision, row.int(1) != revision { throw StoreError.conflict }
            return row.text(2)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    static func search(_ db: SQLiteDatabase, query: String, filter: LibraryFilter,
                       limit: Int, offset: Int = 0, keyboard: Bool = false) throws -> [SnippetSummary] {
        guard filter != .drafts else { return [] }
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned = filter == .pinned ? " AND pinned=1" : ""
        let matching = key.isEmpty ? "" : " AND instr(search_key,?)>0"
        var values: [SQLValue] = [.int(filter == .trash ? 1 : 0)]
        if !key.isEmpty { values.append(.text(key)) }
        values += [.int(max(1, limit)), .int(max(0, offset))]
        let usage = keyboard ? "0,NULL" : "use_count,last_used"
        let order = keyboard ? "pinned DESC,updated DESC,id ASC"
            : filter == .trash ? "updated DESC,id ASC" : "use_count DESC,updated DESC,id ASC"
        return try db.rows("""
            SELECT id,title,substr(body,1,180),pinned,revision,\(usage) FROM snippets
            WHERE deleted=?\(pinned)\(matching)
            ORDER BY \(order) LIMIT ? OFFSET ?
            """, values, map: summaryRow)
    }

    private static func summaryRow(_ row: SQLRow) throws -> SnippetSummary {
        SnippetSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2),
                       pinned: row.int(3) == 1, revision: row.int(4), useCount: row.int(5),
                       lastUsedAt: row.isNull(6) ? nil : Date(timeIntervalSince1970: row.double(6)))
    }

    static func snippet(_ db: SQLiteDatabase, id: UUID) throws -> Snippet {
        let values = try db.rows("SELECT id,title,body,pinned,revision,updated,deleted,use_count,last_used FROM snippets WHERE id=?",
                                [.text(id.uuidString)]) { row in
            Snippet(id: id, title: row.text(1), body: row.text(2), pinned: row.int(3) == 1,
                    revision: row.int(4), updatedAt: Date(timeIntervalSince1970: row.double(5)), deleted: row.int(6) == 1,
                    useCount: row.int(7), lastUsedAt: row.isNull(8) ? nil : Date(timeIntervalSince1970: row.double(8)))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }
}
