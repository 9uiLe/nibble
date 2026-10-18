import Foundation

/// All decisions about a persisted editing session run inside the caller's
/// write reservation. Metadata checks avoid allocating long stored bodies.
enum DraftQueries {
    private static func target(from value: String) throws -> DraftTarget {
        guard !value.isEmpty else { return .new }
        guard let id = UUID(uuidString: value) else { throw StoreError.database }
        return .snippet(id)
    }

    private static func identifier(for target: DraftTarget) -> String {
        switch target {
        case .new: ""
        case .snippet(let id): id.uuidString
        }
    }

    private static func checkpoint(_ id: UUID, in database: SQLiteDatabase) throws -> Draft.Checkpoint? {
        try database.rows("SELECT snippet_id,base_revision,sequence FROM drafts WHERE id = ?", [.text(id.uuidString)]) { row in
            let destination = try target(from: row.text(0))
            let base = try row.int(1)
            let sequence = try row.int(2)
            try validateOrder(target: destination, base: base, sequence: sequence)
            return Draft.Checkpoint(id: id, target: destination, baseRevision: base, sequence: sequence)
        }.first
    }

    private static func validateOrder(target: DraftTarget, base: Int, sequence: Int) throws {
        guard (0..<Int.max).contains(sequence) else { throw StoreError.database }
        switch target {
        case .new: guard base == 0 else { throw StoreError.database }
        case .snippet: guard base > 0 else { throw StoreError.database }
        }
    }

    private static func qualification(_ input: Draft, in database: SQLiteDatabase) throws -> Draft.Replacement {
        guard input.canPersistSequence else { return .rejected }
        guard let stored = try checkpoint(input.id, in: database) else { throw StoreError.missing }
        guard input.checkpoint.belongsToSameSession(as: stored) else { return .rejected }
        if input.canAutosave(over: stored) { return .newer }
        guard input.sequence == stored.sequence else { return .rejected }
        let content = try database.rows("SELECT title,body FROM drafts WHERE id = ?", [.text(input.id.uuidString)]) {
            (try $0.text(0), try $0.text(1))
        }.first
        guard let content else { throw StoreError.missing }
        return input.replacement(of: stored, title: content.0, body: content.1)
    }

    private static func insert(_ database: SQLiteDatabase, target: DraftTarget, body: String) throws -> Draft {
        let input: Draft
        switch target {
        case .new:
            input = Draft(id: UUID(), target: .new, baseRevision: 0, title: "", body: body)
        case .snippet(let id):
            let saved = try SnippetQueries.snippet(database, id: id)
            guard !saved.deleted else { throw StoreError.missing }
            input = Draft(id: UUID(), target: target, baseRevision: saved.revision, title: saved.title, body: saved.body)
        }
        try database.execute("""
            INSERT INTO drafts(id,snippet_id,base_revision,title,body,sequence,updated) VALUES(?,?,?,?,?,?,?)
            """, [.text(input.id.uuidString), .text(identifier(for: input.target)), .int(input.baseRevision),
                  .text(input.title), .text(input.body), .int(input.sequence), .real(Date().timeIntervalSince1970)])
        return input
    }

    static func beginDraft(_ database: SQLiteDatabase, target: DraftTarget, body: String) throws -> Draft {
        try database.writeTransaction { try insert(database, target: target, body: body) }
    }

    static func editingDraft(_ database: SQLiteDatabase, for id: UUID) throws -> Draft {
        try database.writeTransaction {
            try SnippetQueries.requireSaved(database, id: id)
            let previous = try database.rows("SELECT id FROM drafts WHERE snippet_id = ? ORDER BY updated DESC,id ASC LIMIT 1",
                                             [.text(id.uuidString)]) { try $0.uuid(0) }.first
            guard let previous else { return try insert(database, target: .snippet(id), body: "") }
            return try draft(database, id: previous)
        }
    }

    static func drafts(_ database: SQLiteDatabase, limit: Int) throws -> [DraftSummary] {
        try database.rows("""
            SELECT id,substr(title,1,\(SnippetText.previewLength)),substr(body,1,\(SnippetText.previewLength)),updated
            FROM drafts ORDER BY updated DESC,id ASC LIMIT ?
            """, [.int(max(1, limit))]) { row in
            try DraftSummary(id: row.uuid(0), title: row.text(1), preview: row.text(2),
                             updatedAt: Date(timeIntervalSince1970: row.double(3)))
        }
    }

    static func draft(_ database: SQLiteDatabase, id: UUID) throws -> Draft {
        let found = try database.rows("SELECT snippet_id,base_revision,title,body,sequence FROM drafts WHERE id = ?", [.text(id.uuidString)]) { row in
            let destination = try target(from: row.text(0))
            let base = try row.int(1)
            let sequence = try row.int(4)
            try validateOrder(target: destination, base: base, sequence: sequence)
            return try Draft(id: id, target: destination, baseRevision: base,
                             title: row.text(2), body: row.text(3), sequence: sequence)
        }.first
        guard let found else { throw StoreError.missing }
        return found
    }

    private static func write(_ input: Draft, in database: SQLiteDatabase) throws {
        try database.execute("UPDATE drafts SET title = ?, body = ?, sequence = ?, updated = ? WHERE id = ?",
                             [.text(input.title), .text(input.body), .int(input.sequence),
                              .real(Date().timeIntervalSince1970), .text(input.id.uuidString)])
    }

    private static func remove(_ id: UUID, in database: SQLiteDatabase) throws {
        try database.execute("DELETE FROM drafts WHERE id = ?", [.text(id.uuidString)])
    }

    static func updateDraft(_ input: Draft, in database: SQLiteDatabase) throws {
        guard input.canPersistSequence else { throw StoreError.staleDraft }
        try database.writeTransaction {
            guard let previous = try checkpoint(input.id, in: database), input.canAutosave(over: previous) else { return }
            try write(input, in: database)
        }
    }

    static func keepDraft(_ input: Draft, in database: SQLiteDatabase) throws {
        try database.writeTransaction {
            let permission = try qualification(input, in: database)
            guard permission != .rejected else { throw StoreError.staleDraft }
            switch (input.isDisposable, permission) {
            case (true, _): try remove(input.id, in: database)
            case (false, .newer): try write(input, in: database)
            case (false, .identical): break
            case (false, .rejected): throw StoreError.staleDraft
            }
        }
    }

    static func discardDraft(_ input: Draft, in database: SQLiteDatabase) throws {
        try database.writeTransaction {
            guard try qualification(input, in: database) != .rejected else { throw StoreError.staleDraft }
            try remove(input.id, in: database)
        }
    }

    static func save(_ input: Draft, mode: DraftSaveMode, in database: SQLiteDatabase) throws -> UUID {
        try SnippetText.validate(title: input.title, body: input.body)
        return try database.writeTransaction {
            let mayRemove: Bool
            do {
                mayRemove = try qualification(input, in: database) != .rejected
            } catch StoreError.missing where mode == .saveAsNew {
                mayRemove = false
            }
            guard mayRemove || mode == .saveAsNew else { throw StoreError.staleDraft }
            let key = SnippetText.searchKey(input.title + "\n" + input.body)
            let savedID: UUID
            switch (mode, input.target) {
            case (.save, .snippet(let id)):
                savedID = id
                try database.execute("""
                    UPDATE snippets SET title = ?, body = ?, search_key = ?, updated = ?, revision = revision + 1
                    WHERE id = ? AND revision = ? AND deleted = 0 AND revision > 0 AND revision < ?
                    """, [.text(input.title), .text(input.body), .text(key), .real(Date().timeIntervalSince1970),
                          .text(id.uuidString), .int(input.baseRevision), .int(Int.max)])
                guard database.changes == 1 else { throw StoreError.conflict }
            case (.save, .new), (.saveAsNew, _):
                savedID = UUID()
                try database.execute("""
                    INSERT INTO snippets(id,title,body,search_key,pinned,revision,updated,deleted)
                    VALUES(?,?,?,?,0,1,?,0)
                    """, [.text(savedID.uuidString), .text(input.title), .text(input.body), .text(key), .real(Date().timeIntervalSince1970)])
            }
            if mayRemove { try remove(input.id, in: database) }
            return savedID
        }
    }
}
