import Foundation

/// Saved-text queries shared by writable stores and the keyboard's read-only connection.
enum SnippetQueries {
    static func search(_ db: SQLiteDatabase, query: String, filter: LibraryFilter,
                       limit: Int, offset: Int = 0) throws -> [SnippetSummary] {
        guard filter != .drafts else { return [] }
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned = filter == .pinned ? " AND pinned=1" : ""
        let matching = key.isEmpty ? "" : " AND instr(search_key,?)>0"
        var values: [SQLValue] = [.int(filter == .trash ? 1 : 0)]
        if !key.isEmpty { values.append(.text(key)) }
        values += [.int(max(1, limit)), .int(max(0, offset))]
        return try db.rows("""
            SELECT id,title,substr(body,1,180),pinned,revision FROM snippets
            WHERE deleted=?\(pinned)\(matching)
            ORDER BY pinned DESC,updated DESC,id ASC LIMIT ? OFFSET ?
            """, values) { row in
            SnippetSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2),
                           pinned: row.int(3) == 1, revision: row.int(4))
        }
    }

    static func snippet(_ db: SQLiteDatabase, id: UUID) throws -> Snippet {
        let values = try db.rows("SELECT id,title,body,pinned,revision,updated,deleted FROM snippets WHERE id=?",
                                [.text(id.uuidString)]) { row in
            Snippet(id: id, title: row.text(1), body: row.text(2), pinned: row.int(3) == 1,
                    revision: row.int(4), updatedAt: Date(timeIntervalSince1970: row.double(5)), deleted: row.int(6) == 1)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }
}
