import Foundation
import Testing
import Tasking
@testable import Nibble

@Suite("Snippet usage and cleanup candidates")
struct SnippetUsageTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func concurrentConnectionsCountEachCompletedCopyOnce() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "並行コピー")
        let other = SnippetStore(location: files.url)
        let uses = (0..<4).map { SnippetUse(id: UUID(), snippetID: id, completedAt: instant.addingTimeInterval(Double($0))) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for use in uses {
                group.addTask { try await files.store.recordUse(use) }
                group.addTask { try await other.recordUse(use) }
            }
            try await group.waitForAll()
        }
        let item = try await other.snippet(id)
        #expect(item.useCount == 4 && item.lastUsedAt == uses.last?.completedAt)
    }

    @Test @MainActor func cancellationAfterCopyStillPersistsTheAdmittedUse() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "コピー後の記録")
        let tasks = ViewTaskStore()
        let recorder = PausedUsageRecorder(store: files.store)
        let model = LibraryModel(store: files.store, effects: RecordingLibraryEffects(), usageRecorder: recorder, now: { instant })
        tasks.start(id: "copy.then.cancel", lifetime: .screenBound) { _ in await model.copy(id) }
        await recorder.waitForRecord()
        tasks.cancelAll()
        recorder.resume()
        await tasks.waitForIdle()
        #expect(try await files.store.snippet(id).useCount == 1)
        #expect(try await files.store.snippet(id).lastUsedAt == instant)
    }

    @Test @MainActor func refreshReevaluatesTimeWithoutModifyingUsage() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "時間経過")
        try await files.store.recordUse(SnippetUse(id: UUID(), snippetID: id, completedAt: instant))
        var clock = instant.addingTimeInterval(720 * 3600 - 1)
        let model = LibraryModel(store: files.store, effects: RecordingLibraryEffects(), now: { clock })
        await model.refresh()
        #expect(!model.items[0].isDeletionCandidate(at: model.evaluatedAt))
        clock = clock.addingTimeInterval(1)
        await model.refresh()
        #expect(model.items[0].isDeletionCandidate(at: model.evaluatedAt))
        #expect(try await files.store.snippet(id).useCount == 1)
    }

    @Test func retriesAreIdempotentAndLateRecordsDoNotMoveLastUseBackwards() async throws {
        let instant = Date(timeIntervalSinceReferenceDate: 0.0000001)
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "原文")
        let original = try await files.store.snippet(id)
        let earlier = SnippetUse(id: UUID(), snippetID: id, completedAt: instant)
        let later = SnippetUse(id: UUID(), snippetID: id, completedAt: instant.addingTimeInterval(1))
        try await files.store.recordUse(later)
        let other = SnippetStore(location: files.url)
        try await other.recordUse(earlier)
        try await other.recordUse(later)
        try await files.store.recordUse(earlier)
        let result = try await other.snippet(id)
        #expect(result.useCount == 2 && result.lastUsedAt?.timeIntervalSince1970 == later.completedAt.timeIntervalSince1970)
        #expect(result.revision == original.revision && result.updatedAt == original.updatedAt)
        await #expect(throws: StoreError.conflict) {
            try await other.recordUse(SnippetUse(id: earlier.id, snippetID: UUID(), completedAt: instant))
        }
    }

    @Test func failedWriteRollsBackReceiptAndBothUsageFields() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "保持")
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("CREATE TRIGGER reject_usage BEFORE UPDATE OF use_count ON snippets BEGIN SELECT RAISE(ABORT,'fixture'); END")
        let use = SnippetUse(id: UUID(), snippetID: id, completedAt: instant)
        await #expect(throws: StoreError.database) { try await files.store.recordUse(use) }
        #expect(try await files.store.snippet(id).useCount == 0)
        #expect(try await files.store.snippet(id).lastUsedAt == nil)
        try db.execute("DROP TRIGGER reject_usage")
        try await files.store.recordUse(use)
        #expect(try await files.store.snippet(id).useCount == 1)
        #expect(try await files.store.snippet(id).lastUsedAt == instant)
    }

    @Test func usageOrderBreaksTiesByEditTimeThenIDWithoutPartitioningPins() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        _ = try await files.store.search()
        let db = try SQLiteDatabase(url: files.url)
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let d = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let e = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        // Explicit persisted times/IDs make every ordering tie intentional.
        for (id, uses, updated, pinned) in [(a, 2, 1000, 1), (b, 2, 2000, 0), (c, 2, 2000, 1), (d, 3, 0, 0), (e, 0, 3000, 0)] {
            try db.execute("INSERT INTO snippets(id,title,body,search_key,pinned,revision,updated,deleted,use_count) VALUES(?,'項目','本文','本文',?,1,?,0,?)",
                           [.text(id.uuidString), .int(pinned), .int(updated), .int(uses)])
        }
        #expect(try await files.store.search().map(\.id) == [d, b, c, a, e])
        #expect(try await files.store.search(filter: .pinned).map(\.id) == [c, a])
        try db.execute("UPDATE snippets SET updated=3000 WHERE id=?", [.text(a.uuidString)])
        #expect(try await files.store.search().map(\.id) == [d, a, b, c, e])
    }

    @Test func pageExpansionHasNoMissingOrDuplicatedRows() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        _ = try await files.store.search()
        let db = try SQLiteDatabase(url: files.url)
        let ids = (1...201).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        try db.writeTransaction {
            for id in ids {
                try db.execute("INSERT INTO snippets(id,title,body,search_key,pinned,revision,updated,deleted,use_count) VALUES(?,'項目','本文','本文',0,1,1000,0,0)", [.text(id.uuidString)])
            }
        }
        let first = try await files.store.library(LibraryRequest())
        let second = try await files.store.library(LibraryRequest().expanded)
        let full = try await files.store.library(LibraryRequest().expanded.expanded)
        #expect(first.items.map(\.id) == Array(ids.prefix(100)) && first.hasMore)
        #expect(second.items.map(\.id) == Array(ids.prefix(200)) && second.hasMore)
        #expect(full.items.map(\.id) == ids && !full.hasMore)
    }

    @Test func candidateBoundaryUsesElapsedHoursAndRequiresRecordedUse() {
        let never = SnippetSummary(id: UUID(), title: "", preview: "", pinned: false, revision: 1)
        #expect(!never.isDeletionCandidate(at: instant))
        let pinned = SnippetSummary(id: UUID(), title: "", preview: "", pinned: true, revision: 1,
                                    useCount: 1, lastUsedAt: instant)
        #expect(!pinned.isDeletionCandidate(at: instant.addingTimeInterval(720 * 3600 - 0.001)))
        #expect(pinned.isDeletionCandidate(at: instant.addingTimeInterval(720 * 3600)))
    }

    @Test func editingDeletionAndRestorationPreserveUsage() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "元の本文")
        try await files.store.recordUse(SnippetUse(id: UUID(), snippetID: id, completedAt: instant))
        var draft = try await files.store.editingDraft(for: id)
        draft.body = "編集した本文"
        try await files.store.save(draft)
        try await files.store.setPinned(true, id: id)
        _ = try await files.store.mutate(.delete, id: id)
        #expect(try await files.store.search().isEmpty)
        let reopened = SnippetStore(location: files.url)
        _ = try await reopened.mutate(.restore, id: id)
        let result = try await reopened.snippet(id)
        #expect(result.useCount == 1 && result.lastUsedAt == instant && result.pinned)
        #expect(result.body == draft.body)
        let newID = try await create(reopened, body: "共有取り込み相当の新規本文")
        #expect(try await reopened.snippet(newID).useCount == 0)
        #expect(try await reopened.snippet(newID).lastUsedAt == nil)
        _ = try await reopened.mutate(.delete, id: id)
        _ = try await reopened.mutate(.permanentlyDelete, id: id)
        let db = try SQLiteDatabase(url: files.url)
        #expect(try db.rows("SELECT count(*) FROM snippet_uses", []) { $0.int(0) } == [0])
    }

    @Test func versionOneMigrationPreservesOriginalBytesAndDrafts() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("CREATE TABLE snippets(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL)")
        try db.execute("CREATE INDEX snippets_order ON snippets(deleted,pinned DESC,updated DESC,id)")
        try db.execute("CREATE TABLE drafts(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)")
        try db.execute("PRAGMA user_version=1")
        let id = UUID(), deleted = UUID(), draftID = UUID()
        let text = "  か\u{3099}\0\n👩🏽‍💻  "
        for (value, trashed) in [(id, 0), (deleted, 1)] {
            try db.execute("INSERT INTO snippets VALUES(?,?,?,?,1,7,123,?)",
                           [.text(value.uuidString), .text("題名"), .text(text), .text("検索"), .int(trashed)])
        }
        try db.execute("INSERT INTO drafts VALUES(?,?,7,?,?,3,456)",
                       [.text(draftID.uuidString), .text(id.uuidString), .text("未保存"), .text(text)])
        // The new keyboard remains usable before the app has opened/migrated its DB.
        let reader = KeyboardReader(location: { files.url })
        #expect(try await reader.page(KeyboardRequest()).items.map(\.id) == [id])
        let value = try await files.store.snippet(id)
        let trash = try await files.store.snippet(deleted)
        let draft = try await files.store.draft(draftID)
        #expect(value.body.utf8.elementsEqual(text.utf8) && value.title == "題名")
        #expect(value.revision == 7 && value.updatedAt == Date(timeIntervalSince1970: 123) && value.pinned)
        #expect(value.useCount == 0 && value.lastUsedAt == nil && !value.deleted && trash.deleted)
        #expect(draft.body.utf8.elementsEqual(text.utf8) && draft.title == "未保存" && draft.sequence == 3)
        #expect(try db.rows("PRAGMA user_version", []) { $0.int(0) } == [2])
        #expect(try await reader.page(KeyboardRequest()).items.map(\.id) == [id])
        _ = try await SnippetStore(location: files.url).search()
        #expect(try await files.store.snippet(id).useCount == 0)
    }

    @Test @MainActor func copiesAcrossModelsUpdateOneRecordAndClearCandidate() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "検索の本文")
        try await files.store.recordUse(SnippetUse(id: UUID(), snippetID: id, completedAt: instant.addingTimeInterval(-720 * 3600)))
        let effects = RecordingLibraryEffects()
        let all = LibraryModel(store: files.store, effects: effects, now: { instant })
        let search = LibraryModel(store: files.store, effects: effects, now: { instant })
        search.query = "検索"
        await all.refresh()
        #expect(all.items[0].isDeletionCandidate(at: all.evaluatedAt))
        await all.copy(id)
        await search.copy(id)
        #expect(try await files.store.snippet(id).useCount == 3)
        #expect(search.items[0].lastUsedAt == instant && search.query == "検索")
        #expect(!search.items[0].isDeletionCandidate(at: search.evaluatedAt))
        #expect(effects.events == [.copy("検索の本文"), .announce("コピーしました"), .copy("検索の本文"), .announce("コピーしました")])
        await search.copy(UUID())
        #expect(try await files.store.snippet(id).useCount == 3)
    }

    @Test(arguments: [false, true]) @MainActor
    func recordFailureCanRetryWithoutCopyingOrCountingTwice(committed: Bool) async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "一度だけコピー")
        let effects = RecordingLibraryEffects()
        let recorder = OnceFailingUsageRecorder(store: files.store, committed: committed)
        let model = LibraryModel(store: files.store, effects: effects, usageRecorder: recorder, now: { instant })
        await model.copy(id)
        #expect(model.notice?.message == "コピーしました" && model.failure?.recovery == .retryUsage)
        #expect(model.failure?.title.contains("コピー済み") == true)
        #expect(model.failure?.message.contains("コピー回数と最後にコピーした日時の記録だけ") == true)
        #expect(try await files.store.snippet(id).useCount == (committed ? 1 : 0))
        await model.retryUsageRecording()
        await model.retryUsageRecording()
        #expect(model.failure == nil)
        #expect(try await files.store.snippet(id).useCount == 1)
        #expect(try await files.store.snippet(id).lastUsedAt == instant)
        #expect(effects.events == [.copy("一度だけコピー"), .announce("コピーしました")])
    }

    @Test @MainActor func permanentlyDeletedPendingUseCanBeAcknowledged() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "削除する本文")
        let effects = RecordingLibraryEffects()
        let model = LibraryModel(store: files.store, effects: effects,
                                 usageRecorder: OnceFailingUsageRecorder(store: files.store, committed: false))
        await model.copy(id)
        #expect(model.failure?.recovery == .retryUsage)
        let trash = SnippetStore(location: files.url)
        _ = try await trash.mutate(.delete, id: id)
        _ = try await trash.mutate(.permanentlyDelete, id: id)
        await model.retryUsageRecording()
        #expect(model.failure?.recovery == .dismiss)
        model.dismissFailure()
        await model.retryUsageRecording()
        #expect(model.failure == nil && model.items.isEmpty)
        #expect(effects.events == [.copy("削除する本文"), .announce("コピーしました")])
    }
}

@MainActor private final class PausedUsageRecorder: SnippetUsageRecording {
    let store: SnippetStore
    private var continuation: CheckedContinuation<Void, Never>?
    init(store: SnippetStore) { self.store = store }
    func recordUse(_ use: SnippetUse) async throws {
        await withCheckedContinuation { continuation = $0 }
        try await store.recordUse(use)
    }
    func waitForRecord() async { while continuation == nil { await Task.yield() } }
    func resume() { continuation?.resume(); continuation = nil }
}

private actor OnceFailingUsageRecorder: SnippetUsageRecording {
    let store: SnippetStore
    let committed: Bool
    private var shouldFail = true
    init(store: SnippetStore, committed: Bool) { self.store = store; self.committed = committed }
    func recordUse(_ use: SnippetUse) async throws {
        if shouldFail {
            shouldFail = false
            if committed { try await store.recordUse(use) }
            throw StoreError.database
        }
        try await store.recordUse(use)
    }
}
