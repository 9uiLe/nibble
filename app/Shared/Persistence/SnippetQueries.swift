import Foundation

/// Saved-text queries shared by writable stores and the keyboard's read-only connection.
enum SnippetQueries {
    static func requireSaved(_ db: SQLiteDatabase, id: UUID) throws {
        let deleted = try db.rows("SELECT deleted FROM snippets WHERE id=?", [.text(id.uuidString)]) { try $0.bool(0) }
        guard deleted.first == false else { throw StoreError.missing }
    }

    static func summary(_ db: SQLiteDatabase, id: UUID, includesUsage: Bool = true) throws -> SnippetSummary {
        let usage = includesUsage ? "use_count,last_used" : "NULL,NULL"
        let values = try db.rows("SELECT id,title,substr(body,1,\(SnippetText.previewLength)),pinned,revision,\(usage),deleted FROM snippets WHERE id=?",
                                [.text(id.uuidString)]) { row in
            _ = try row.bool(7)
            return try summaryRow(row, includesUsage: includesUsage)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    /// Read only the body. Validate the row before allocating its full text in Swift.
    static func savedBody(_ db: SQLiteDatabase, id: UUID, revision: Int? = nil) throws -> String {
        let values = try db.rows("SELECT deleted,revision,body FROM snippets WHERE id=?", [.text(id.uuidString)]) { row in
            guard try !row.bool(0) else { throw StoreError.missing }
            if let revision, try row.int(1) != revision { throw StoreError.conflict }
            return try row.text(2)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    static func search(_ db: SQLiteDatabase, query: String, filter: LibraryFilter,
                       limit: Int, offset: Int = 0, ordering: SnippetOrdering? = nil, includesUsage: Bool = true) throws -> [SnippetSummary] {
        guard filter != .drafts else { return [] }
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned = filter == .pinned ? " AND pinned=1" : ""
        let matching = key.isEmpty ? "" : " AND instr(search_key,?)>0"
        var values: [SQLValue] = [.int(filter == .trash ? 1 : 0)]
        if !key.isEmpty { values.append(.text(key)) }
        values += [.int(max(1, limit)), .int(max(0, offset))]
        let usage = includesUsage ? "use_count,last_used" : "NULL,NULL"
        let order: String
        switch ordering ?? filter.ordering {
        case .mostUsed: order = "use_count DESC,updated DESC,id ASC"
        case .recentlyUpdated: order = "updated DESC,id ASC"
        case .pinnedFirst: order = "pinned DESC,updated DESC,id ASC"
        }
        return try db.rows("""
            SELECT id,title,substr(body,1,\(SnippetText.previewLength)),pinned,revision,\(usage) FROM snippets
            WHERE deleted=?\(pinned)\(matching)
            ORDER BY \(order) LIMIT ? OFFSET ?
            """, values) { try summaryRow($0, includesUsage: includesUsage) }
    }

    private static func summaryRow(_ row: SQLRow, includesUsage: Bool) throws -> SnippetSummary {
        let usage: SnippetUsage?
        if includesUsage {
            usage = try usageRow(row, countColumn: 5, dateColumn: 6)
        } else {
            guard row.isNull(5), row.isNull(6) else { throw StoreError.database }
            usage = nil
        }
        return SnippetSummary(id: try row.uuid(0), title: try row.text(1), preview: try row.text(2),
                              pinned: try row.bool(3), revision: try row.int(4), usage: usage)
    }

    private static func usageRow(_ row: SQLRow, countColumn: Int32, dateColumn: Int32) throws -> SnippetUsage {
        let count = try row.int(countColumn)
        let date: Date?
        if row.isNull(dateColumn) {
            date = nil
        } else {
            date = Date(timeIntervalSince1970: try row.double(dateColumn))
        }
        guard let usage = SnippetUsage(count: count, lastUsedAt: date) else { throw StoreError.database }
        return usage
    }

    static func snippet(_ db: SQLiteDatabase, id: UUID) throws -> Snippet {
        let values = try db.rows("SELECT id,title,body,pinned,revision,updated,deleted,use_count,last_used FROM snippets WHERE id=?",
                                [.text(id.uuidString)]) { row in
            Snippet(id: id, title: try row.text(1), body: try row.text(2), pinned: try row.bool(3),
                    revision: try row.int(4), updatedAt: Date(timeIntervalSince1970: try row.double(5)), deleted: try row.bool(6),
                    usage: try usageRow(row, countColumn: 7, dateColumn: 8))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }
}
