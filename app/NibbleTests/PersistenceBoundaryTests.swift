import Foundation
import Testing
@testable import Nibble

@Suite("SQLite representation boundaries")
struct PersistenceBoundaryTests {
    @Test func invalidTypesAreRejectedAndEmptyTextIsNotNull() throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let database = try SQLiteDatabase(url: fixture.url)
        _ = try database.rows("SELECT '',NULL,2,'12',CAST(X'FF' AS TEXT),1,0", []) { row in
            let empty = try row.text(0)
            let enabled = try row.bool(5)
            let disabled = try row.bool(6)
            #expect(empty.isEmpty)
            #expect(throws: StoreError.database) { try row.text(1) }
            #expect(throws: StoreError.database) { try row.int(1) }
            #expect(throws: StoreError.database) { try row.bool(2) }
            #expect(throws: StoreError.database) { try row.int(3) }
            #expect(throws: StoreError.database) { try row.text(4) }
            #expect(enabled && !disabled)
        }
    }

    @Test func statementLeasesKeepRowsAliveThroughNestedReadsEvictionAndErrors() throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let database = try SQLiteDatabase(url: fixture.url)
        let sql = "SELECT ? UNION ALL SELECT ?"
        let rows = try database.rows(sql, [.text("a\0b"), .text("か\u{3099}")]) { row in
            let nested = try database.rows(sql, [.text("内1"), .text("内2")]) { try $0.text(0) }
            for index in 0..<40 { try database.execute("SELECT \(index)") }
            return (try row.text(0), nested)
        }
        #expect(rows[0].0.utf8.elementsEqual("a\0b".utf8))
        #expect(rows[1].0.utf8.elementsEqual("か\u{3099}".utf8))
        #expect(rows.allSatisfy { $0.1 == ["内1", "内2"] })
        #expect(throws: StoreError.database) { try database.execute(sql, [.text("不完全")]) }
        #expect(try database.rows(sql, [.text(""), .text("次")]) { try $0.text(0) } == ["", "次"])
    }

    @Test func futureAndCorruptStoresAreNotReplaced() async throws {
        for corrupt in [false, true] {
            let fixture = try TestDatabase()
            defer { fixture.removeFiles() }
            if corrupt {
                try Data(repeating: 0xFF, count: 4096).write(to: fixture.url)
            } else {
                let database = try SQLiteDatabase(url: fixture.url)
                try database.execute("PRAGMA user_version = 99")
            }
            let original = try Data(contentsOf: fixture.url)
            await #expect(throws: corrupt ? StoreError.database : StoreError.newerVersion) {
                try await fixture.store.search()
            }
            #expect(try Data(contentsOf: fixture.url) == original)
        }
    }

    @Test func malformedFlagsUsageAndDraftTargetsDoNotBecomeNormalValues() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "原文")
        let input = try await fixture.store.beginDraft(body: "未保存")
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("UPDATE snippets SET pinned = 2 WHERE id = ?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.summary(id) }
        try database.execute("UPDATE snippets SET pinned = 0, use_count = 1, last_used = NULL WHERE id = ?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.snippet(id) }
        try database.execute("UPDATE snippets SET use_count = 0, deleted = 2 WHERE id = ?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.savedBody(id) }
        #expect(try database.rows("SELECT snippet_id FROM drafts WHERE id = ?", [.text(input.id.uuidString)]) { try $0.text(0) } == [""])
        try database.execute("UPDATE drafts SET snippet_id = 'unknown' WHERE id = ?", [.text(input.id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.draft(input.id) }
    }

    @Test func anUnversionedForeignDatabaseIsRejectedWithoutChangingItsFileOrSchema() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("CREATE TABLE foreign_notes(id INTEGER PRIMARY KEY,body TEXT NOT NULL)")
        try database.execute("CREATE INDEX foreign_lookup ON foreign_notes(body)")
        try database.execute("INSERT INTO foreign_notes VALUES(1,?)", [.text(" 他のアプリの原文\0か\u{3099} ")])
        let originalFile = try Data(contentsOf: fixture.url)
        let originalSchema = try database.rows("SELECT name,sql FROM sqlite_schema ORDER BY name", []) {
            try $0.text(0) + ":" + $0.text(1)
        }
        let journal = try database.rows("PRAGMA journal_mode", []) { try $0.text(0) }
        await #expect(throws: StoreError.database) { try await fixture.store.search() }
        let resultingSchema = try database.rows("SELECT name,sql FROM sqlite_schema ORDER BY name", []) {
            try $0.text(0) + ":" + $0.text(1)
        }
        #expect(resultingSchema == originalSchema)
        #expect(try database.rows("PRAGMA user_version", []) { try $0.int(0) } == [0])
        #expect(try database.rows("PRAGMA journal_mode", []) { try $0.text(0) } == journal)
        let retained = try database.rows("SELECT body FROM foreign_notes WHERE id=1", []) { try $0.text(0) }
        #expect(retained.first?.utf8.elementsEqual(" 他のアプリの原文\0か\u{3099} ".utf8) == true)
        #expect(try Data(contentsOf: fixture.url) == originalFile)
    }

    @Test(arguments: [-1, Int.max])
    func malformedDraftOrderCannotBeRestoredOrOverwritten(sequence: Int) async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        var input = try await fixture.store.beginDraft(body: " 既存の下書き\0 ")
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("UPDATE drafts SET sequence=? WHERE id=?", [.int(sequence), .text(input.id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.draft(input.id) }
        input.body = "上書きしてはいけない"
        await #expect(throws: StoreError.database) { try await fixture.store.updateDraft(input) }
        let stored = try database.rows("SELECT sequence,body FROM drafts WHERE id=?", [.text(input.id.uuidString)]) {
            (try $0.int(0), try $0.text(1))
        }
        #expect(stored.first?.0 == sequence)
        #expect(stored.first?.1.utf8.elementsEqual(" 既存の下書き\0 ".utf8) == true)
    }

    @Test func anExhaustedRevisionDoesNotBecomeSqliteRealAndCanBeRecoveredAsNew() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "保存済み")
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("UPDATE snippets SET revision=? WHERE id=?", [.int(Int.max), .text(id.uuidString)])
        var editing = try await fixture.store.editingDraft(for: id)
        editing.body = "回復する編集"
        await #expect(throws: StoreError.conflict) { try await fixture.store.save(editing) }
        await #expect(throws: StoreError.conflict) { try await fixture.store.setPinned(true, id: id) }
        await #expect(throws: StoreError.conflict) { try await fixture.store.mutate(.delete, id: id) }
        let reader = KeyboardReader(location: { fixture.url })
        let item = try #require(try await reader.page(KeyboardRequest()).items.first)
        await #expect(throws: KeyboardReadError.changed) { try await reader.setPinned(true, for: item) }
        let beforeRecovery = try await fixture.store.snippet(id)
        #expect(beforeRecovery.revision == Int.max && !beforeRecovery.deleted && !beforeRecovery.pinned)
        #expect(try database.rows("SELECT typeof(revision) FROM snippets WHERE id=?", [.text(id.uuidString)]) { try $0.text(0) } == ["integer"])
        let recovered = try await fixture.store.save(editing, mode: .saveAsNew)
        #expect(recovered != id)
        #expect(try await fixture.store.savedBody(recovered) == "回復する編集")
        #expect(try await fixture.store.savedBody(id) == "保存済み")
        try database.execute("UPDATE snippets SET revision=-1 WHERE id=?", [.text(id.uuidString)])
        await #expect(throws: StoreError.database) { try await fixture.store.snippet(id) }
        await #expect(throws: StoreError.database) { try await fixture.store.setPinned(true, id: id) }
    }

    @Test func entitlementSnapshotsDistinguishAbsentInvalidAndExpired() {
        let now = Date(timeIntervalSince1970: 100)
        #expect(ProEntitlement(stored: nil, now: now) == .absent)
        #expect(ProEntitlement(stored: "", now: now) == .invalid)
        #expect(ProEntitlement(stored: 101, now: now) == .invalid)
        #expect(ProEntitlement(stored: Date(timeIntervalSince1970: .nan), now: now) == .invalid)
        #expect(ProEntitlement(stored: now, now: now) == .expired(at: now))
        #expect(ProEntitlement(stored: now.addingTimeInterval(1), now: now).isActive)
    }
}
