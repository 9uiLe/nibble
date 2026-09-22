import Foundation

/// Draft lifecycle and optimistic conflict checks stay inside synchronous database transactions.
enum DraftQueries {
    /// Creates a distinct editing session. The library uses editingDraft(for:) to resume one.
    static func beginDraft(_ db: SQLiteDatabase, snippetID: UUID?, body: String) throws -> Draft {
        try db.writeTransaction { try insertDraft(snippetID: snippetID, body: body, into: db) }
    }

    /// Lookup and creation share one write transaction, even across app/extension connections.
    static func editingDraft(_ db: SQLiteDatabase, for snippetID: UUID) throws -> Draft {
        try db.writeTransaction {
            try SnippetQueries.requireSaved(db, id: snippetID)
            let existing = try db.rows("SELECT id FROM drafts WHERE snippet_id=? ORDER BY updated DESC,id LIMIT 1",
                                       [.text(snippetID.uuidString)]) { try $0.uuid(0) }
            if let id = existing.first { return try draft(db, id: id) }
            return try insertDraft(snippetID: snippetID, body: "", into: db)
        }
    }

    private static func insertDraft(snippetID: UUID?, body: String, into db: SQLiteDatabase) throws -> Draft {
        let snippet = try snippetID.map { try SnippetQueries.snippet(db, id: $0) }
        guard snippet?.deleted != true else { throw StoreError.missing }
        let draft = Draft(id: UUID(), snippetID: snippetID, baseRevision: snippet?.revision ?? 0,
                          title: snippet?.title ?? "", body: snippet?.body ?? body)
        try db.execute("INSERT INTO drafts(id,snippet_id,base_revision,title,body,sequence,updated) VALUES(?,?,?,?,?,0,?)",
            [.text(draft.id.uuidString), .text(snippetID?.uuidString ?? ""), .int(draft.baseRevision),
             .text(draft.title), .text(draft.body), .real(Date().timeIntervalSince1970)])
        return draft
    }

    static func drafts(_ db: SQLiteDatabase, limit: Int) throws -> [DraftSummary] {
        try db.rows("SELECT id,substr(title,1,\(SnippetText.previewLength)),substr(body,1,\(SnippetText.previewLength)),updated FROM drafts ORDER BY updated DESC,id LIMIT ?",
                            [.int(max(1, limit))]) { row in
            DraftSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2),
                         updatedAt: Date(timeIntervalSince1970: row.double(3)))
        }
    }

    static func draft(_ db: SQLiteDatabase, id: UUID) throws -> Draft {
        let values = try db.rows("SELECT snippet_id,base_revision,title,body,sequence FROM drafts WHERE id=?",
                                         [.text(id.uuidString)]) { row in
            let target = row.text(0)
            return Draft(id: id, snippetID: target.isEmpty ? nil : try row.uuid(0), baseRevision: row.int(1),
                         title: row.text(2), body: row.text(3), sequence: row.int(4))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    static func updateDraft(_ draft: Draft, in db: SQLiteDatabase) throws {
        try db.writeTransaction {
            guard let stored = try checkpoint(draft.id, in: db), draft.canAutosave(over: stored) else { return }
            try writeDraft(draft, in: db)
        }
    }

    private static func writeDraft(_ draft: Draft, in db: SQLiteDatabase) throws {
        // The caller holds the write transaction that admitted this exact session.
        try db.execute("UPDATE drafts SET title=?,body=?,sequence=?,updated=? WHERE id=?",
            [.text(draft.title), .text(draft.body), .int(draft.sequence), .real(Date().timeIntervalSince1970),
             .text(draft.id.uuidString)])
    }

    static func keepDraft(_ snapshot: Draft, in db: SQLiteDatabase) throws {
        try db.writeTransaction {
            let replacement = try replacement(snapshot, in: db)
            guard replacement != .rejected else { throw StoreError.staleDraft }
            if snapshot.isDisposable { try removeDraft(snapshot.id, from: db) }
            else if replacement == .newer { try writeDraft(snapshot, in: db) }
        }
    }

    static func discardDraft(_ snapshot: Draft, in db: SQLiteDatabase) throws {
        try db.writeTransaction {
            guard try replacement(snapshot, in: db) != .rejected else { throw StoreError.staleDraft }
            try removeDraft(snapshot.id, from: db)
        }
    }

    private static func removeDraft(_ id: UUID, from db: SQLiteDatabase) throws {
        try db.execute("DELETE FROM drafts WHERE id=?", [.text(id.uuidString)])
    }

    @discardableResult
    static func save(_ draft: Draft, asNew: Bool, in db: SQLiteDatabase) throws -> UUID {
        try SnippetText.validate(title: draft.title, body: draft.body)
        let id = asNew ? UUID() : (draft.snippetID ?? UUID())
        let key = SnippetText.searchKey(draft.title + "\n" + draft.body)
        try db.writeTransaction {
            let replacesDraft: Bool
            do { replacesDraft = try replacement(draft, in: db) != .rejected }
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

    /// Read content only for equal input sequences. Newer input needs identity metadata only.
    /// CASE keeps full text out of both SQLite result values and Swift strings on that path.
    private static func replacement(_ snapshot: Draft, in db: SQLiteDatabase) throws -> Draft.Replacement {
        let matches = try db.rows("""
            SELECT snippet_id,base_revision,sequence,
                   CASE WHEN sequence=? THEN title END,
                   CASE WHEN sequence=? THEN body END
            FROM drafts WHERE id=?
            """, [.int(snapshot.sequence), .int(snapshot.sequence), .text(snapshot.id.uuidString)]) { row in
            let stored = Draft.Checkpoint(id: snapshot.id, snippetID: row.text(0).isEmpty ? nil : try row.uuid(0),
                                          baseRevision: row.int(1), sequence: row.int(2))
            return snapshot.replacement(of: stored, title: row.text(3), body: row.text(4))
        }
        guard let match = matches.first else { throw StoreError.missing }
        return match
    }

    private static func checkpoint(_ id: UUID, in db: SQLiteDatabase) throws -> Draft.Checkpoint? {
        try db.rows("SELECT snippet_id,base_revision,sequence FROM drafts WHERE id=?", [.text(id.uuidString)]) { row in
            Draft.Checkpoint(id: id, snippetID: row.text(0).isEmpty ? nil : try row.uuid(0),
                             baseRevision: row.int(1), sequence: row.int(2))
        }.first
    }
}
