import Foundation
import Testing
@testable import Nibble

@Suite("Persistence boundaries")
struct PersistenceBoundaryTests {
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
            let result = try db.rows("SELECT text FROM values_under_test WHERE id=?", [.int(index)]) { $0.text(0) }
            #expect(result.count == 1)
            #expect(result[0].utf8.elementsEqual(value.utf8))
        }
        #expect(throws: StoreError.database) {
            try db.execute("INSERT INTO values_under_test VALUES(?,?)", [.int(99)])
        }
        try db.execute("INSERT INTO values_under_test VALUES(?,?)", [.int(99), .text("after error")])
        #expect(try db.rows("SELECT text FROM values_under_test WHERE id=?", [.int(99)]) { $0.text(0) } == ["after error"])
    }

    @Test func nestedReadAndCacheEvictionDoNotInvalidateActiveRows() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        let sql = "SELECT ? UNION ALL SELECT ?"
        let result = try db.rows(sql, [.int(1), .int(2)]) { outer in
            let inner = try db.rows(sql, [.int(3), .int(4)]) { $0.int(0) }
            // More than the cache budget while the outer statement is still leased.
            for number in 0..<64 { _ = try db.rows("SELECT \(number)", []) { $0.int(0) } }
            return [outer.int(0)] + inner
        }
        #expect(result == [[1, 3, 4], [2, 3, 4]])
        #expect(throws: StoreError.missing) { try db.rows(sql, [.int(1), .int(2)]) { _ in throw StoreError.missing } }
        #expect(try db.rows(sql, [.int(5), .int(6)]) { $0.int(0) } == [5, 6])
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
