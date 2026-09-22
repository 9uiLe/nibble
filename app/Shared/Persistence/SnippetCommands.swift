import Foundation

/// Synchronous write transactions. No UI effect or suspension can occur before commit.
enum SnippetCommands {
    static func recordUse(_ use: SnippetUse, in db: SQLiteDatabase) throws {
        guard use.completedAt.timeIntervalSince1970.isFinite else { throw StoreError.database }
        try db.writeTransaction {
            let existing = try db.rows("SELECT snippet_id,used FROM snippet_uses WHERE id=?", [.text(use.id.uuidString)]) {
                (snippetID: try $0.uuid(0), timestamp: $0.double(1))
            }
            if let existing = existing.first {
                // Compare in SQLite's epoch representation: converting back to Date
                // can round away precision and reject the original operation's retry.
                guard existing.snippetID == use.snippetID,
                      existing.timestamp == use.completedAt.timeIntervalSince1970 else { throw StoreError.conflict }
                return
            }
            try db.execute("INSERT INTO snippet_uses(id,snippet_id,used) VALUES(?,?,?)",
                           [.text(use.id.uuidString), .text(use.snippetID.uuidString), .real(use.completedAt.timeIntervalSince1970)])
            try db.execute("""
                UPDATE snippets SET use_count=use_count+1,
                    last_used=CASE WHEN last_used IS NULL OR last_used<? THEN ? ELSE last_used END
                WHERE id=? AND use_count<?
                """, [.real(use.completedAt.timeIntervalSince1970), .real(use.completedAt.timeIntervalSince1970),
                       .text(use.snippetID.uuidString), .int(Int.max)])
            if db.changes != 1 {
                let exists = try db.rows("SELECT 1 FROM snippets WHERE id=?", [.text(use.snippetID.uuidString)]) { $0.int(0) }
                throw exists.isEmpty ? StoreError.missing : StoreError.database
            }
        }
    }

    static func apply(_ mutation: SnippetMutation, id: UUID, to db: SQLiteDatabase) throws -> SnippetSummary {
        try db.writeTransaction {
            let item = try SnippetQueries.summary(db, id: id)
            switch mutation {
            case .delete: try setDeleted(true, id: id, in: db)
            case .restore: try setDeleted(false, id: id, in: db)
            case .permanentlyDelete: try remove(id, from: db)
            }
            return item
        }
    }

    static func setPinned(_ pinned: Bool, id: UUID, revision: Int? = nil, in db: SQLiteDatabase) throws {
        let matching = revision == nil ? "" : " AND revision=?"
        var values: [SQLValue] = [.int(pinned ? 1 : 0), .text(id.uuidString)]
        if let revision { values.append(.int(revision)) }
        try db.execute("UPDATE snippets SET pinned=?,revision=revision+1 WHERE id=? AND deleted=0\(matching)", values)
        guard db.changes == 1 else { throw revision == nil ? StoreError.missing : StoreError.conflict }
    }

    static func setDeleted(_ deleted: Bool, id: UUID, in db: SQLiteDatabase) throws {
        try db.execute("UPDATE snippets SET deleted=?,updated=?,revision=revision+1 WHERE id=?",
            [.int(deleted ? 1 : 0), .real(Date().timeIntervalSince1970), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
    }

    static func remove(_ id: UUID, from db: SQLiteDatabase) throws {
        try db.execute("DELETE FROM snippets WHERE id=? AND deleted=1", [.text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
        try db.execute("DELETE FROM drafts WHERE snippet_id=?", [.text(id.uuidString)])
        try db.execute("DELETE FROM snippet_uses WHERE snippet_id=?", [.text(id.uuidString)])
    }
}
