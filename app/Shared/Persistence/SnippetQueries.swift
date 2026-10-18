import Foundation

/// A shared projection keeps the keyboard on schema 1 without reading columns
/// introduced in schema 2. Full bodies are fetched only for a selected UUID.
enum SnippetQueries {
    private static func projection(usage: Bool) -> String {
        let columns = "id,title,pinned,revision,substr(body,1,\(SnippetText.previewLength))"
        return usage ? columns + ",use_count,last_used" : columns
    }

    private static func decodeSummary(_ row: SQLRow, usage: Bool) throws -> SnippetSummary {
        let revision = try validRevision(row, at: 3)
        let observation: SnippetUsage? = usage ? try decodeUsage(row, count: 5, timestamp: 6) : nil
        return try SnippetSummary(id: row.uuid(0), title: row.text(1), preview: row.text(4),
                                  pinned: row.bool(2), revision: revision, usage: observation)
    }

    private static func validRevision(_ row: SQLRow, at column: Int32) throws -> Int {
        let number = try row.int(column)
        guard number > 0 else { throw StoreError.database }
        return number
    }

    private static func decodeUsage(_ row: SQLRow, count: Int32, timestamp: Int32) throws -> SnippetUsage {
        let date = row.isNull(timestamp) ? nil : try Date(timeIntervalSince1970: row.double(timestamp))
        guard let observation = try SnippetUsage(count: row.int(count), lastUsedAt: date) else { throw StoreError.database }
        return observation
    }

    static func requireSaved(_ database: SQLiteDatabase, id: UUID) throws {
        let flags = try database.rows("SELECT deleted,revision FROM snippets WHERE id = ?", [.text(id.uuidString)]) {
            _ = try validRevision($0, at: 1)
            return try $0.bool(0)
        }
        guard flags.first == false else { throw StoreError.missing }
    }

    static func summary(_ database: SQLiteDatabase, id: UUID, includesUsage: Bool = true,
                        requiredDeleted: Bool? = nil) throws -> SnippetSummary {
        let sql = "SELECT \(projection(usage: includesUsage)),deleted FROM snippets WHERE id = ?"
        let result = try database.rows(sql, [.text(id.uuidString)]) { row in
            let deleted = try row.bool(includesUsage ? 7 : 5)
            if let requiredDeleted {
                guard deleted == requiredDeleted else { throw StoreError.missing }
            }
            return try decodeSummary(row, usage: includesUsage)
        }
        guard let result = result.first else { throw StoreError.missing }
        return result
    }

    static func savedBody(_ database: SQLiteDatabase, id: UUID, revision: Int? = nil) throws -> String {
        let result = try database.rows("SELECT revision,deleted,body FROM snippets WHERE id = ?", [.text(id.uuidString)]) { row in
            let current = try validRevision(row, at: 0)
            guard try !row.bool(1) else { throw StoreError.missing }
            if let revision {
                guard current == revision else { throw StoreError.conflict }
            }
            return try row.text(2)
        }
        guard let result = result.first else { throw StoreError.missing }
        return result
    }

    static func snippet(_ database: SQLiteDatabase, id: UUID) throws -> Snippet {
        let result = try database.rows("""
            SELECT title,body,pinned,revision,updated,deleted,use_count,last_used
            FROM snippets WHERE id = ?
            """, [.text(id.uuidString)]) { row in
            try Snippet(id: id, title: row.text(0), body: row.text(1), pinned: row.bool(2), revision: validRevision(row, at: 3),
                        updatedAt: Date(timeIntervalSince1970: row.double(4)), deleted: row.bool(5),
                        usage: decodeUsage(row, count: 6, timestamp: 7))
        }
        guard let result = result.first else { throw StoreError.missing }
        return result
    }

    static func search(_ database: SQLiteDatabase, query: String, filter: LibraryFilter,
                       limit: Int, offset: Int = 0, ordering: SnippetOrdering? = nil, includesUsage: Bool = true) throws -> [SnippetSummary] {
        guard filter != .drafts else { return [] }
        var predicates = ["deleted = ?"]
        var bindings: [SQLValue] = [.int(filter == .trash ? 1 : 0)]
        if filter == .pinned { predicates.append("pinned = 1") }
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            predicates.append("instr(search_key, ?) > 0")
            bindings.append(.text(key))
        }
        let order: String
        switch ordering ?? filter.ordering {
        case .pinnedFirst: order = "pinned DESC, updated DESC, id ASC"
        case .recentlyUpdated: order = "updated DESC, id ASC"
        case .mostUsed: order = "use_count DESC, updated DESC, id ASC"
        }
        bindings.append(contentsOf: [.int(max(1, limit)), .int(max(0, offset))])
        return try database.rows("""
            SELECT \(projection(usage: includesUsage)) FROM snippets
            WHERE \(predicates.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?
            """, bindings) { try decodeSummary($0, usage: includesUsage) }
    }
}
