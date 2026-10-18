import Foundation
import OSLog

/// The actor owns one prepared writer connection. Its transactions are entirely
/// synchronous, including a batch of retained collections and their counts.
actor SnippetStore: LibraryStorage, DraftEditing {
    private let resolveLocation: @Sendable () throws -> URL
    private var writer: SQLiteDatabase?
    private let measurements = OSSignposter(subsystem: "nibble.9uiLe.com", category: "Store")

    init(location: URL) { resolveLocation = { location } }
    init(location: @escaping @Sendable () throws -> URL) { resolveLocation = location }

    private func open() throws -> SQLiteDatabase {
        guard let writer else {
            let destination = try resolveLocation()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            let connection = try SQLiteDatabase(url: destination)
            try SnippetSchema.prepare(connection, at: destination)
            self.writer = connection
            return connection
        }
        return writer
    }

    func libraries(_ requests: [LibraryRequest]) throws -> [LibraryPage] {
        try Task.checkCancellation()
        let database = try open()
        return try database.readTransaction {
            guard let counts = try database.rows("""
                SELECT count(*),coalesce(sum(pinned),0),(SELECT count(*) FROM drafts)
                FROM snippets WHERE deleted = 0
                """, [], map: { try LibraryCounts(saved: $0.int(0), pinned: $0.int(1), drafts: $0.int(2)) }).first else {
                throw StoreError.database
            }
            return try requests.map { request in
                try Task.checkCancellation()
                return try page(request, counts: counts, database: database)
            }
        }
    }

    private func page(_ request: LibraryRequest, counts: LibraryCounts, database: SQLiteDatabase) throws -> LibraryPage {
        switch request.filter {
        case .drafts:
            let loaded = try DraftQueries.drafts(database, limit: request.limit + 1)
            return LibraryPage(drafts: Array(loaded.prefix(request.limit)), hasMore: loaded.count > request.limit, counts: counts)
        case .all, .pinned, .trash:
            let loaded = try SnippetQueries.search(database, query: request.query, filter: request.filter, limit: request.limit + 1)
            let pending = request.includesDrafts
                ? try DraftQueries.drafts(database, limit: LibraryRequest.draftPreviewLimit + 1) : []
            return LibraryPage(items: Array(loaded.prefix(request.limit)), drafts: Array(pending.prefix(LibraryRequest.draftPreviewLimit)),
                               hasMore: loaded.count > request.limit, hasMoreDrafts: pending.count > LibraryRequest.draftPreviewLimit,
                               counts: counts)
        }
    }

    func search(_ query: String = "", filter: LibraryFilter = .all, limit: Int = LibraryRequest.pageSize) throws -> [SnippetSummary] {
        try Task.checkCancellation()
        let timing = measurements.beginInterval("Search")
        defer { measurements.endInterval("Search", timing) }
        return try SnippetQueries.search(open(), query: query, filter: filter, limit: limit)
    }

    func snippet(_ id: UUID) throws -> Snippet { try SnippetQueries.snippet(open(), id: id) }
    func summary(_ id: UUID) throws -> SnippetSummary { try SnippetQueries.summary(open(), id: id) }
    func savedBody(_ id: UUID) throws -> String { try SnippetQueries.savedBody(open(), id: id) }

    func beginDraft(target: DraftTarget = .new, body: String = "") throws -> Draft {
        try DraftQueries.beginDraft(open(), target: target, body: body)
    }

    func editingDraft(for id: UUID) throws -> Draft { try DraftQueries.editingDraft(open(), for: id) }
    func draft(_ id: UUID) throws -> Draft { try DraftQueries.draft(open(), id: id) }
    func drafts(limit: Int = Int.max) throws -> [DraftSummary] { try DraftQueries.drafts(open(), limit: limit) }
    func updateDraft(_ draft: Draft) throws { try DraftQueries.updateDraft(draft, in: open()) }
    func keepDraft(_ draft: Draft) throws { try DraftQueries.keepDraft(draft, in: open()) }
    func discardDraft(_ draft: Draft) throws { try DraftQueries.discardDraft(draft, in: open()) }

    @discardableResult
    func save(_ draft: Draft, mode: DraftSaveMode = .save) throws -> UUID {
        let timing = measurements.beginInterval("Save")
        defer { measurements.endInterval("Save", timing) }
        return try DraftQueries.save(draft, mode: mode, in: open())
    }

    func recordUse(_ use: SnippetUse) throws {
        // The OS effect has happened already. Admit the receipt even if its
        // screen's task was cancelled after the pasteboard write.
        try SnippetCommands.recordUse(use, in: open())
    }

    func setPinned(_ pinned: Bool, id: UUID) throws {
        let database = try open()
        try database.writeTransaction { try SnippetCommands.setPinned(pinned, id: id, in: database) }
    }

    @discardableResult
    func mutate(_ mutation: SnippetMutation, id: UUID) throws -> SnippetSummary {
        try SnippetCommands.apply(mutation, id: id, to: open())
    }
}
