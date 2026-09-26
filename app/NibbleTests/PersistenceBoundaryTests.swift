import Foundation
import Testing
@testable import Nibble

@Suite("Persistence boundaries")
struct PersistenceBoundaryTests {
    @Test func sqliteValuesKeepEmptyNullAndUnknownFlagsDistinct() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        _ = try db.rows("SELECT '', NULL, 2, 1, 0, '12', CAST(X'FF' AS TEXT)", []) { row in
            let empty = try row.text(0)
            let enabled = try row.bool(3)
            let disabled = try row.bool(4)
            #expect(empty.isEmpty)
            #expect(throws: StoreError.database) { try row.text(1) }
            #expect(throws: StoreError.database) { try row.int(1) }
            #expect(throws: StoreError.database) { try row.bool(2) }
            #expect(enabled)
            #expect(!disabled)
            #expect(throws: StoreError.database) { try row.int(5) }
            #expect(throws: StoreError.database) { try row.text(6) }
        }
    }

    @Test func malformedSavedFlagsFailInsteadOfBecomingFalseOrMissing() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "原文")
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("UPDATE snippets SET pinned=2 WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.snippet(id) }
        await #expect(throws: StoreError.database) { try await files.store.summary(id) }
        try db.execute("UPDATE snippets SET pinned=0,deleted=2 WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.savedBody(id) }
        await #expect(throws: StoreError.database) { try await files.store.snippet(id) }
        await #expect(throws: StoreError.database) { try await files.store.mutate(.delete, id: id) }
    }

    @Test func draftTargetRetainsLegacyEmptyEncodingAndRejectsUnknownValues() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let fresh = try await files.store.beginDraft(body: "本文")
        #expect(try await files.store.draft(fresh.id).target == .new)
        let savedID = try await create(files.store, body: "保存済み")
        let editing = try await files.store.beginDraft(target: .snippet(savedID))
        #expect(try await files.store.draft(editing.id).target == .snippet(savedID))
        let db = try SQLiteDatabase(url: files.url)
        #expect(try db.rows("SELECT snippet_id FROM drafts WHERE id=?", [.text(fresh.id.uuidString)]) { try $0.text(0) } == [""])
        try db.execute("UPDATE drafts SET snippet_id='unknown' WHERE id=?", [.text(fresh.id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.draft(fresh.id) }
        try db.execute("UPDATE drafts SET snippet_id='' WHERE id=?", [.text(fresh.id.uuidString)])
        #expect(try await files.store.draft(fresh.id).target == .new)
    }

    @Test func usageRejectsContradictoryCountAndTimestamp() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, body: "本文")
        #expect(try await files.store.snippet(id).usage == .never)
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("UPDATE snippets SET use_count=1,last_used=NULL WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.snippet(id) }
        await #expect(throws: StoreError.database) { try await files.store.summary(id) }
        try db.execute("UPDATE snippets SET use_count=0,last_used=1000 WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.snippet(id) }
        try db.execute("UPDATE snippets SET use_count=2,last_used=1000 WHERE id=?", [.text(id.uuidString)])
        #expect(try await files.store.snippet(id).usage.count == 2)
        try db.execute("UPDATE snippets SET last_used='invalid' WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await files.store.snippet(id) }
    }

    @Test @MainActor func mutationNoticeUsesCommittedDataInsteadOfCachedRows() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let id = try await create(files.store, title: "一覧の古い題名", body: "本文")
        let model = LibraryModel(store: files.store)
        await model.refresh()
        let otherProcess = SnippetStore(location: files.url)
        var draft = try await otherProcess.editingDraft(for: id)
        draft.title = "別の画面で更新した題名"
        try await otherProcess.save(draft)
        await model.delete(id)
        #expect(model.notice?.subject == draft.title)
        #expect(try await files.store.snippet(id).deleted)
        await model.restore(id)
        #expect(model.notice?.subject == draft.title)
        #expect(try await !files.store.snippet(id).deleted)
    }

    @Test func reusedStatementsReplaceEveryBindingAndKeepOriginalBytes() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("CREATE TABLE values_under_test(id INTEGER PRIMARY KEY, text TEXT)")
        let values = ["", "a\0b", "か\u{3099}", "bindを切り替える本文", "短文"]
        for (index, value) in values.enumerated() {
            try db.execute("INSERT INTO values_under_test VALUES(?,?)", [.int(index), .text(value)])
            let result = try db.rows("SELECT text FROM values_under_test WHERE id=?", [.int(index)]) { try $0.text(0) }
            #expect(result.count == 1)
            #expect(result[0].utf8.elementsEqual(value.utf8))
        }
        #expect(throws: StoreError.database) {
            try db.execute("INSERT INTO values_under_test VALUES(?,?)", [.int(99)])
        }
        try db.execute("INSERT INTO values_under_test VALUES(?,?)", [.int(99), .text("after error")])
        #expect(try db.rows("SELECT text FROM values_under_test WHERE id=?", [.int(99)]) { try $0.text(0) } == ["after error"])
    }

    @Test func nestedReadAndCacheEvictionDoNotInvalidateActiveRows() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        let sql = "SELECT ? UNION ALL SELECT ?"
        let result = try db.rows(sql, [.int(1), .int(2)]) { outer in
            let inner = try db.rows(sql, [.int(3), .int(4)]) { try $0.int(0) }
            // More than the cache budget while the outer statement is still leased.
            for number in 0..<64 { _ = try db.rows("SELECT \(number)", []) { try $0.int(0) } }
            return [try outer.int(0)] + inner
        }
        #expect(result == [[1, 3, 4], [2, 3, 4]])
        #expect(throws: StoreError.missing) { try db.rows(sql, [.int(1), .int(2)]) { _ in throw StoreError.missing } }
        #expect(try db.rows(sql, [.int(5), .int(6)]) { try $0.int(0) } == [5, 6])
    }

    @Test func cachedReadsSeeOtherConnectionsAndFilterPredicatesStayIndependent() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let first = files.store
        let second = SnippetStore(location: files.url)
        let id = try await create(first, body: "か\u{3099} %_\\ literal")
        _ = try await first.library(LibraryRequest())
        try await second.setPinned(true, id: id)
        #expect(try await first.search("%_\\", filter: .pinned).map(\.id) == [id])
        #expect(try await first.search("missing", filter: .pinned).isEmpty)
        try await second.mutate(.delete, id: id)
        #expect(try await first.search().isEmpty)
        #expect(try await first.search("が", filter: .trash).map(\.id) == [id])
        try await second.mutate(.restore, id: id)
        #expect(try await first.search("が").map(\.id) == [id])
    }

    @Test @MainActor func effectsFollowSuccessfulReadsAndNeverRunForMissingOrDeletedItems() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let effects = RecordingLibraryEffects()
        let model = LibraryModel(store: files.store, effects: effects)
        let text = "  か\u{3099}\0\n👩🏽‍💻  "
        let id = try await create(files.store, body: text)
        await model.copy(id)
        #expect(effects.events == [.copy(text), .announce("コピーしました")])
        guard case .copy(let copied) = effects.events.first else {
            Issue.record("The successful read must reach the copy effect")
            return
        }
        #expect(copied.utf8.elementsEqual(text.utf8))
        #expect(model.feedback == 1 && model.notice?.message == "コピーしました")
        try await files.store.mutate(.delete, id: id)
        await model.copy(id)
        await model.copy(UUID())
        #expect(effects.events.count == 2 && model.feedback == 1)
        #expect(model.failure?.recovery == .reload)
    }

}
