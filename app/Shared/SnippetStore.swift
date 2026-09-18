import Foundation
import OSLog

/// All connections and prepared statements stay on this actor. Transactions never suspend.
actor SnippetStore: LibraryReading {
    private let location: @Sendable () throws -> URL
    private var connection: SQLiteDatabase?
    private let signposter = OSSignposter(subsystem: "nibble.9uiLe.com", category: "Store")

    init(location: URL) { self.location = { location } }
    init(location: @escaping @Sendable () throws -> URL) { self.location = location }

    private func database() throws -> SQLiteDatabase {
        if let connection { return connection }
        let url = try location()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        let db = try SQLiteDatabase(url: url)
        try SnippetSchema.prepare(db, at: url)
        connection = db
        return db
    }

    func library(_ request: LibraryRequest) throws -> LibraryPage {
        try Task.checkCancellation()
        let db = try database()
        return try db.readTransaction {
            if request.filter == .drafts {
                let values = try drafts(limit: request.limit + 1)
                return LibraryPage(drafts: Array(values.prefix(request.limit)), hasMore: values.count > request.limit)
            }
            let values = try search(request.query, filter: request.filter, limit: request.limit + 1)
            let drafts = request.filter == .all ? try drafts(limit: LibraryRequest.draftPreviewLimit + 1) : []
            return LibraryPage(items: Array(values.prefix(request.limit)),
                               drafts: Array(drafts.prefix(LibraryRequest.draftPreviewLimit)),
                               hasMore: values.count > request.limit,
                               hasMoreDrafts: drafts.count > LibraryRequest.draftPreviewLimit)
        }
    }

    func search(_ query: String = "", filter: LibraryFilter = .all, limit: Int = 100) throws -> [SnippetSummary] {
        let interval = signposter.beginInterval("Search")
        defer { signposter.endInterval("Search", interval) }
        try Task.checkCancellation()
        // Drafts are editing sessions, exposed by library(_:) rather than saved-snippet search.
        guard filter != .drafts else { return [] }
        let key = SnippetText.searchKey(query).trimmingCharacters(in: .whitespacesAndNewlines)
        // instr treats %, _ and backslash literally and supports one-character Japanese queries.
        let db = try database()
        // SQL varies only by these fixed predicates; user text is always bound.
        // A pinned request can seek directly into the (deleted, pinned, updated, id) index.
        let pinned = filter == .pinned ? " AND pinned=1" : ""
        let matching = key.isEmpty ? "" : " AND instr(search_key,?)>0"
        var values: [SQLValue] = [.int(filter == .trash ? 1 : 0)]
        if !key.isEmpty { values.append(.text(key)) }
        values.append(.int(max(1, limit)))
        return try db.rows("""
            SELECT id,title,substr(body,1,180),pinned,revision FROM snippets
            WHERE deleted=?\(pinned)\(matching)
            ORDER BY pinned DESC,updated DESC,id ASC LIMIT ?
            """, values) { row in
            return SnippetSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2), pinned: row.int(3) == 1, revision: row.int(4))
        }
    }

    func summary(_ id: UUID) throws -> SnippetSummary {
        let values = try database().rows("SELECT id,title,substr(body,1,180),pinned,revision FROM snippets WHERE id=?",
                                         [.text(id.uuidString)]) { row in
            SnippetSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2), pinned: row.int(3) == 1, revision: row.int(4))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    func snippet(_ id: UUID) throws -> Snippet {
        let values = try database().rows("SELECT id,title,body,pinned,revision,updated,deleted FROM snippets WHERE id=?", [.text(id.uuidString)]) { row in
            Snippet(id: id, title: row.text(1), body: row.text(2), pinned: row.int(3) == 1,
                    revision: row.int(4), updatedAt: Date(timeIntervalSince1970: row.double(5)), deleted: row.int(6) == 1)
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    /// Creates a distinct editing session. The library uses editingDraft(for:) to resume one.
    func beginDraft(snippetID: UUID? = nil, body: String = "") throws -> Draft {
        let db = try database()
        return try db.writeTransaction { try insertDraft(snippetID: snippetID, body: body, into: db) }
    }

    /// Lookup and creation share one write transaction, even across app/extension connections.
    func editingDraft(for snippetID: UUID) throws -> Draft {
        let db = try database()
        return try db.writeTransaction {
            guard try !snippet(snippetID).deleted else { throw StoreError.missing }
            let existing = try db.rows("SELECT id FROM drafts WHERE snippet_id=? ORDER BY updated DESC,id LIMIT 1",
                                       [.text(snippetID.uuidString)]) { try $0.uuid(0) }
            if let id = existing.first { return try draft(id) }
            return try insertDraft(snippetID: snippetID, body: "", into: db)
        }
    }

    private func insertDraft(snippetID: UUID?, body: String, into db: SQLiteDatabase) throws -> Draft {
        let snippet = try snippetID.map { try self.snippet($0) }
        guard snippet?.deleted != true else { throw StoreError.missing }
        let draft = Draft(id: UUID(), snippetID: snippetID, baseRevision: snippet?.revision ?? 0,
                          title: snippet?.title ?? "", body: snippet?.body ?? body)
        try db.execute("INSERT INTO drafts(id,snippet_id,base_revision,title,body,sequence,updated) VALUES(?,?,?,?,?,0,?)",
            [.text(draft.id.uuidString), .text(snippetID?.uuidString ?? ""), .int(draft.baseRevision),
             .text(draft.title), .text(draft.body), .real(Date().timeIntervalSince1970)])
        return draft
    }

    func drafts(limit: Int = Int.max) throws -> [DraftSummary] {
        try database().rows("SELECT id,substr(title,1,180),substr(body,1,180),updated FROM drafts ORDER BY updated DESC,id LIMIT ?",
                            [.int(max(1, limit))]) { row in
            DraftSummary(id: try row.uuid(0), title: row.text(1), preview: row.text(2),
                         updatedAt: Date(timeIntervalSince1970: row.double(3)))
        }
    }

    func draft(_ id: UUID) throws -> Draft {
        let values = try database().rows("SELECT snippet_id,base_revision,title,body,sequence FROM drafts WHERE id=?",
                                         [.text(id.uuidString)]) { row in
            let target = row.text(0)
            return Draft(id: id, snippetID: target.isEmpty ? nil : try row.uuid(0), baseRevision: row.int(1),
                         title: row.text(2), body: row.text(3), sequence: row.int(4))
        }
        guard let value = values.first else { throw StoreError.missing }
        return value
    }

    func updateDraft(_ draft: Draft) throws {
        // UPDATE only: a late queued write cannot resurrect a saved/discarded draft.
        try database().execute("UPDATE drafts SET title=?,body=?,sequence=?,updated=? WHERE id=? AND sequence<?",
            [.text(draft.title), .text(draft.body), .int(draft.sequence), .real(Date().timeIntervalSince1970),
             .text(draft.id.uuidString), .int(draft.sequence)])
    }

    func keepDraft(_ snapshot: Draft) throws {
        let db = try database()
        try db.writeTransaction {
            guard try snapshot.canReplace(draft(snapshot.id)) else { throw StoreError.staleDraft }
            if snapshot.isDisposable { try removeDraft(snapshot.id, from: db) }
            else { try updateDraft(snapshot) }
        }
    }

    func discardDraft(_ snapshot: Draft) throws {
        let db = try database()
        try db.writeTransaction {
            guard try snapshot.canReplace(draft(snapshot.id)) else { throw StoreError.staleDraft }
            try removeDraft(snapshot.id, from: db)
        }
    }

    private func removeDraft(_ id: UUID, from db: SQLiteDatabase) throws {
        try db.execute("DELETE FROM drafts WHERE id=?", [.text(id.uuidString)])
    }

    @discardableResult
    func save(_ draft: Draft, asNew: Bool = false) throws -> UUID {
        let interval = signposter.beginInterval("Save")
        defer { signposter.endInterval("Save", interval) }
        try SnippetText.validate(title: draft.title, body: draft.body)
        let db = try database()
        let id = asNew ? UUID() : (draft.snippetID ?? UUID())
        let key = SnippetText.searchKey(draft.title + "\n" + draft.body)
        try db.writeTransaction {
            let replacesDraft: Bool
            do { replacesDraft = try draft.canReplace(self.draft(draft.id)) }
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

    func setPinned(_ pinned: Bool, id: UUID) throws {
        let db = try database()
        try db.execute("UPDATE snippets SET pinned=?,revision=revision+1 WHERE id=? AND deleted=0", [.int(pinned ? 1 : 0), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
    }

    func setDeleted(_ deleted: Bool, id: UUID) throws {
        let db = try database()
        try db.execute("UPDATE snippets SET deleted=?,updated=?,revision=revision+1 WHERE id=?",
            [.int(deleted ? 1 : 0), .real(Date().timeIntervalSince1970), .text(id.uuidString)])
        guard db.changes == 1 else { throw StoreError.missing }
    }

    func permanentlyDelete(_ id: UUID) throws {
        let db = try database()
        try db.writeTransaction {
            try db.execute("DELETE FROM snippets WHERE id=? AND deleted=1", [.text(id.uuidString)])
            guard db.changes == 1 else { throw StoreError.missing }
            try db.execute("DELETE FROM drafts WHERE snippet_id=?", [.text(id.uuidString)])
        }
    }
}
