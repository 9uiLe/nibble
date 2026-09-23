import Foundation
import OSLog

/// All connections and prepared statements stay on this actor. Transactions never suspend.
actor SnippetStore: LibraryStorage, DraftEditing {
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

    /// All retained filters and their counts describe one database snapshot.
    func libraries(_ requests: [LibraryRequest]) throws -> [LibraryPage] {
        try Task.checkCancellation()
        let db = try database()
        return try db.readTransaction {
            let counts = try libraryCounts(db)
            return try requests.map { request in
                try libraryPage(request, counts: counts)
            }
        }
    }

    private func libraryPage(_ request: LibraryRequest, counts: LibraryCounts) throws -> LibraryPage {
        if request.filter == .drafts {
            let values = try drafts(limit: request.limit + 1)
            return LibraryPage(drafts: Array(values.prefix(request.limit)), hasMore: values.count > request.limit,
                               counts: counts)
        }
        let values = try search(request.query, filter: request.filter, limit: request.limit + 1)
        let drafts = request.includesDrafts ? try drafts(limit: LibraryRequest.draftPreviewLimit + 1) : []
        return LibraryPage(items: Array(values.prefix(request.limit)),
                           drafts: Array(drafts.prefix(LibraryRequest.draftPreviewLimit)),
                           hasMore: values.count > request.limit,
                           hasMoreDrafts: drafts.count > LibraryRequest.draftPreviewLimit, counts: counts)
    }

    private func libraryCounts(_ db: SQLiteDatabase) throws -> LibraryCounts {
        let values = try db.rows("""
            SELECT count(*), coalesce(sum(pinned),0), (SELECT count(*) FROM drafts)
            FROM snippets WHERE deleted=0
            """, []) { row in
            LibraryCounts(saved: row.int(0), pinned: row.int(1), drafts: row.int(2))
        }
        guard let counts = values.first else { throw StoreError.unavailable }
        return counts
    }

    func search(_ query: String = "", filter: LibraryFilter = .all, limit: Int = LibraryRequest.pageSize) throws -> [SnippetSummary] {
        let interval = signposter.beginInterval("Search")
        defer { signposter.endInterval("Search", interval) }
        try Task.checkCancellation()
        guard filter != .drafts else { return [] }
        return try SnippetQueries.search(database(), query: query, filter: filter, limit: limit)
    }

    func summary(_ id: UUID) throws -> SnippetSummary {
        try SnippetQueries.summary(database(), id: id)
    }

    func snippet(_ id: UUID) throws -> Snippet {
        try SnippetQueries.snippet(database(), id: id)
    }

    func beginDraft(snippetID: UUID? = nil, body: String = "") throws -> Draft {
        try DraftQueries.beginDraft(database(), snippetID: snippetID, body: body)
    }

    func editingDraft(for id: UUID) throws -> Draft {
        try DraftQueries.editingDraft(database(), for: id)
    }

    func drafts(limit: Int = Int.max) throws -> [DraftSummary] {
        try DraftQueries.drafts(database(), limit: limit)
    }

    func draft(_ id: UUID) throws -> Draft { try DraftQueries.draft(database(), id: id) }
    func updateDraft(_ draft: Draft) throws { try DraftQueries.updateDraft(draft, in: database()) }
    func keepDraft(_ draft: Draft) throws { try DraftQueries.keepDraft(draft, in: database()) }
    func discardDraft(_ draft: Draft) throws { try DraftQueries.discardDraft(draft, in: database()) }

    @discardableResult
    func save(_ draft: Draft, asNew: Bool = false) throws -> UUID {
        let interval = signposter.beginInterval("Save")
        defer { signposter.endInterval("Save", interval) }
        return try DraftQueries.save(draft, asNew: asNew, in: database())
    }

    func savedBody(_ id: UUID) throws -> String { try SnippetQueries.savedBody(database(), id: id) }

    /// The OS copy has already completed; cancellation must not discard this admitted write.
    func recordUse(_ use: SnippetUse) throws {
        try SnippetCommands.recordUse(use, in: database())
    }

    @discardableResult
    func mutate(_ mutation: SnippetMutation, id: UUID) throws -> SnippetSummary {
        try SnippetCommands.apply(mutation, id: id, to: database())
    }

    func setPinned(_ pinned: Bool, id: UUID) throws {
        try SnippetCommands.setPinned(pinned, id: id, in: database())
    }

}
