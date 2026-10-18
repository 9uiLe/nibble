import Foundation
import Testing
@testable import Nibble

@Suite("Completed copy receipts and migration")
struct SnippetUsageTests {
    @Test func concurrentRetriesCountReceiptsOnceAndDoNotRewindTheLastUse() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "本文")
        let original = try await fixture.store.snippet(id)
        let second = SnippetStore(location: fixture.url)
        let recent = SnippetUse(id: UUID(), snippetID: id, completedAt: Date(timeIntervalSinceReferenceDate: 1.0000001))
        let earlier = SnippetUse(id: UUID(), snippetID: id, completedAt: recent.completedAt.addingTimeInterval(-1))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for store in [fixture.store, second] {
                for receipt in [recent, earlier] {
                    group.addTask { try await store.recordUse(receipt) }
                }
            }
            try await group.waitForAll()
        }
        let saved = try await second.snippet(id)
        #expect(saved.usage.count == 2)
        #expect(saved.usage.lastUsedAt?.timeIntervalSince1970 == recent.completedAt.timeIntervalSince1970)
        #expect(saved.revision == original.revision && saved.updatedAt == original.updatedAt)
        await #expect(throws: StoreError.conflict) {
            try await second.recordUse(SnippetUse(id: recent.id, snippetID: UUID(), completedAt: recent.completedAt))
        }
    }

    @Test func receiptAndAggregateRollbackTogetherAndRetryCanThenSucceed() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "元の値")
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("CREATE TRIGGER block_count BEFORE UPDATE OF use_count ON snippets BEGIN SELECT RAISE(ABORT,'fixture'); END")
        let receipt = SnippetUse(id: UUID(), snippetID: id, completedAt: Date(timeIntervalSince1970: 200))
        await #expect(throws: StoreError.database) { try await fixture.store.recordUse(receipt) }
        #expect(try await fixture.store.snippet(id).usage == .never)
        #expect(try database.rows("SELECT count(*) FROM snippet_uses", []) { try $0.int(0) } == [0])
        try database.execute("DROP TRIGGER block_count")
        try await fixture.store.recordUse(receipt)
        try await fixture.store.recordUse(receipt)
        #expect(try await fixture.store.snippet(id).usage.count == 1)
        try await fixture.store.mutate(.delete, id: id)
        try await fixture.store.mutate(.restore, id: id)
        #expect(try await fixture.store.snippet(id).usage.count == 1)
        try await fixture.store.mutate(.delete, id: id)
        try await fixture.store.mutate(.permanentlyDelete, id: id)
        #expect(try database.rows("SELECT count(*) FROM snippet_uses", []) { try $0.int(0) } == [0])
    }

    @Test func legacySchemaRemainsReadableBeforeAndAfterAMetadataPreservingMigration() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("CREATE TABLE snippets(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,search_key TEXT NOT NULL,pinned INTEGER NOT NULL,revision INTEGER NOT NULL,updated REAL NOT NULL,deleted INTEGER NOT NULL)")
        try database.execute("CREATE TABLE drafts(id TEXT PRIMARY KEY,snippet_id TEXT NOT NULL,base_revision INTEGER NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,sequence INTEGER NOT NULL,updated REAL NOT NULL)")
        try database.execute("PRAGMA user_version = 1")
        let id = UUID(), trash = UUID(), inputID = UUID()
        let bytes = " \tか\u{3099}\0\r\n👩🏽‍💻 "
        for (identifier, deleted) in [(id, 0), (trash, 1)] {
            try database.execute("INSERT INTO snippets VALUES(?,?,?,'検索',1,7,123,?)",
                                 [.text(identifier.uuidString), .text("題名"), .text(bytes), .int(deleted)])
        }
        try database.execute("INSERT INTO drafts VALUES(?,?,7,?,?,3,456)",
                             [.text(inputID.uuidString), .text(id.uuidString), .text("未確定"), .text(bytes)])
        let keyboard = KeyboardReader(location: { fixture.url })
        #expect(try await keyboard.page(KeyboardRequest()).items.map(\.id) == [id])
        let migrated = try await fixture.store.snippet(id)
        let input = try await fixture.store.draft(inputID)
        #expect(migrated.body.utf8.elementsEqual(bytes.utf8) && migrated.title == "題名")
        #expect(migrated.revision == 7 && migrated.pinned && migrated.updatedAt == Date(timeIntervalSince1970: 123))
        #expect(migrated.usage == .never && !migrated.deleted)
        #expect(try await fixture.store.snippet(trash).deleted)
        #expect(input.body.utf8.elementsEqual(bytes.utf8) && input.sequence == 3 && input.baseRevision == 7)
        #expect(input.target == .snippet(id) && input.title == "未確定")
        #expect(try database.rows("PRAGMA user_version", []) { try $0.int(0) } == [2])
        #expect(try await keyboard.page(KeyboardRequest()).items.first?.usage == nil)
        #expect(try await SnippetStore(location: fixture.url).snippet(id).usage == .never)
    }

    @Test func usageOrderingKeepsPinsInTheSameRankingAndCandidateTimeIsDerived() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let a = try await create(fixture.store, body: "ピン")
        let b = try await create(fixture.store, body: "多く使う")
        try await fixture.store.setPinned(true, id: a)
        let instant = Date(timeIntervalSince1970: 100)
        try await fixture.store.recordUse(SnippetUse(id: UUID(), snippetID: a, completedAt: instant))
        for _ in 0..<2 { try await fixture.store.recordUse(SnippetUse(id: UUID(), snippetID: b, completedAt: instant)) }
        #expect(try await fixture.store.search().map(\.id) == [b, a])
        #expect(try await fixture.store.search(filter: .pinned).map(\.id) == [a])
        let usage = try await fixture.store.snippet(a).usage
        #expect(!usage.isDeletionCandidate(at: instant.addingTimeInterval(30 * 86_400 - 1)))
        #expect(usage.isDeletionCandidate(at: instant.addingTimeInterval(30 * 86_400)))
        #expect(!SnippetUsage.never.isDeletionCandidate(at: instant.addingTimeInterval(60 * 86_400)))
    }
}
