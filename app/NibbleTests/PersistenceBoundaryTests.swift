import Foundation
import Testing
@testable import Nibble

@Suite("Persistence boundaries")
struct PersistenceBoundaryTests {
    @Test func reusedStatementsReplaceEveryBindingAndKeepOriginalBytes() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("CREATE TABLE values_under_test(id INTEGER PRIMARY KEY, text TEXT)")
        let values = ["", "a\0b", "か\u{3099}", String(repeating: "長文", count: 50_000), "短文"]
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

    @Test func statementFailureRollsBackAndTheNextTransactionCanCommit() throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("CREATE TABLE values_under_test(id INTEGER PRIMARY KEY)")
        #expect(throws: StoreError.database) {
            try db.writeTransaction {
                try db.execute("INSERT INTO values_under_test VALUES(?)", [.int(1)])
                try db.execute("INSERT INTO values_under_test VALUES(?)", [.int(1)])
            }
        }
        try db.writeTransaction { try db.execute("INSERT INTO values_under_test VALUES(?)", [.int(2)]) }
        #expect(try db.rows("SELECT id FROM values_under_test", []) { $0.int(0) } == [2])
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
        try await second.setDeleted(true, id: id)
        #expect(try await first.search().isEmpty)
        #expect(try await first.search("が", filter: .trash).map(\.id) == [id])
        try await second.setDeleted(false, id: id)
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
        #expect(model.feedback == 1 && model.notice?.message == "コピーしました")
        try await files.store.setDeleted(true, id: id)
        await model.copy(id)
        await model.copy(UUID())
        #expect(effects.events.count == 2 && model.feedback == 1)
        #expect(model.failure?.recovery == .reload)
    }

    @Test @MainActor func unavailableContainerIsReportedAtOperationTime() async {
        let store = SnippetStore(location: { throw StoreError.unavailable })
        let effects = RecordingLibraryEffects()
        let model = LibraryModel(store: store, effects: effects)
        await model.open()
        #expect(model.editor == nil && model.failure != nil)
        #expect(effects.events.isEmpty)
    }
}
