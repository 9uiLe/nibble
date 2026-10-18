import Foundation

enum SnippetCommands {
    static func recordUse(_ receipt: SnippetUse, in database: SQLiteDatabase) throws {
        let timestamp = receipt.completedAt.timeIntervalSince1970
        guard timestamp.isFinite else { throw StoreError.database }
        try database.writeTransaction {
            let prior = try database.rows("SELECT snippet_id,used FROM snippet_uses WHERE id = ?", [.text(receipt.id.uuidString)]) {
                (try $0.uuid(0), try $0.double(1))
            }.first
            if let prior {
                guard prior.0 == receipt.snippetID, prior.1 == timestamp else { throw StoreError.conflict }
                return
            }
            let item = try SnippetQueries.summary(database, id: receipt.snippetID)
            guard let observation = item.usage, observation.count < Int.max else { throw StoreError.database }
            try database.execute("INSERT INTO snippet_uses(id,snippet_id,used) VALUES(?,?,?)",
                                 [.text(receipt.id.uuidString), .text(receipt.snippetID.uuidString), .real(timestamp)])
            try database.execute("""
                UPDATE snippets SET use_count = use_count + 1,
                    last_used = CASE WHEN last_used IS NULL THEN ? ELSE max(last_used, ?) END
                WHERE id = ?
                """, [.real(timestamp), .real(timestamp), .text(receipt.snippetID.uuidString)])
            guard database.changes == 1 else { throw StoreError.missing }
        }
    }

    static func apply(_ mutation: SnippetMutation, id: UUID, to database: SQLiteDatabase) throws -> SnippetSummary {
        try database.writeTransaction {
            let deleted: Bool
            switch mutation {
            case .delete: deleted = false
            case .restore, .permanentlyDelete: deleted = true
            }
            let committedSubject = try SnippetQueries.summary(database, id: id, requiredDeleted: deleted)
            switch mutation {
            case .permanentlyDelete:
                try database.execute("DELETE FROM snippets WHERE id = ? AND deleted = 1", [.text(id.uuidString)])
                guard database.changes == 1 else { throw StoreError.missing }
                for table in ["drafts", "snippet_uses"] {
                    try database.execute("DELETE FROM \(table) WHERE snippet_id = ?", [.text(id.uuidString)])
                }
            case .delete, .restore:
                guard committedSubject.revision < Int.max else { throw StoreError.conflict }
                try database.execute("""
                    UPDATE snippets SET deleted = ?, revision = revision + 1, updated = ?
                    WHERE id = ? AND deleted = ? AND revision > 0 AND revision < ?
                    """, [.int(deleted ? 0 : 1), .real(Date().timeIntervalSince1970), .text(id.uuidString),
                          .int(deleted ? 1 : 0), .int(Int.max)])
                guard database.changes == 1 else { throw StoreError.database }
            }
            return committedSubject
        }
    }

    static func setPinned(_ pinned: Bool, id: UUID, revision: Int? = nil, in database: SQLiteDatabase) throws {
        let metadata = try database.rows("SELECT revision,deleted FROM snippets WHERE id = ?", [.text(id.uuidString)]) {
            (try $0.int(0), try $0.bool(1))
        }.first
        guard let metadata, !metadata.1 else { throw revision == nil ? StoreError.missing : StoreError.conflict }
        guard metadata.0 > 0 else { throw StoreError.database }
        guard metadata.0 < Int.max else { throw StoreError.conflict }
        var predicates = "id = ? AND deleted = 0 AND revision > 0 AND revision < ?"
        var bindings: [SQLValue] = [.int(pinned ? 1 : 0), .text(id.uuidString), .int(Int.max)]
        if let revision {
            predicates += " AND revision = ?"
            bindings.append(.int(revision))
        }
        try database.execute("UPDATE snippets SET pinned = ?, revision = revision + 1 WHERE \(predicates)", bindings)
        guard database.changes == 1 else { throw revision == nil ? StoreError.missing : StoreError.conflict }
    }
}
