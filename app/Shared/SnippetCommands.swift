import Foundation

/// Synchronous write transactions. No UI effect or suspension can occur before commit.
enum SnippetCommands {
    static func apply(_ mutation: SnippetMutation, id: UUID, to db: SQLiteDatabase) throws -> SnippetMutationResult {
        try db.writeTransaction {
            let subject = try SnippetQueries.summary(db, id: id).displayTitle
            switch mutation {
            case .delete: try setDeleted(true, id: id, in: db)
            case .restore: try setDeleted(false, id: id, in: db)
            case .permanentlyDelete: try remove(id, from: db)
            }
            return SnippetMutationResult(subject: subject)
        }
    }

    static func setPinned(_ pinned: Bool, id: UUID, in db: SQLiteDatabase) throws {
        try db.execute("UPDATE snippets SET pinned=?,revision=revision+1 WHERE id=? AND deleted=0",
                       [.int(pinned ? 1 : 0), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
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
    }
}
