import Testing
import UIKit
import SwiftData
import CoreData
import SQLite3
@testable import ResearchProbe

@Suite("Research experiments", .serialized)
@MainActor
struct HostedTests {
    let sample = ProbeValue(id: "a", title: "定型文", body: "  日本語 か\u{3099} ｶﾞ ガ\n\t👩🏽‍💻 <code> _\"()  ")

    func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func record(_ name: String, _ value: some Encodable) throws {
        let url = URL.documentsDirectory.appending(path: "results", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url.appending(path: name + ".json"), options: .atomic)
    }

    @Test func environment() throws {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(version.majorVersion == 26 && version.minorVersion == 5)
        #expect(Bundle.main.bundleIdentifier == "dev.nibble.ResearchProbe")
        let db = try SQLiteProbe(url: directory().appending(path: "db"))
        try record("environment", ["os": ProcessInfo.processInfo.operatingSystemVersionString,
            "sqlite": String(cString: sqlite3_libversion()), "sqliteSourceID": String(cString: sqlite3_sourceid()),
            "compileOptions": try db.rows("PRAGMA compile_options").flatMap { $0 }.joined(separator: "\n")])
    }

    @Test(arguments: ["SwiftData", "CoreData", "SQLite"])
    func crudReopenReadOnly(kind: String) throws {
        let url = try directory().appending(path: "store")
        func open(_ readOnly: Bool = false) throws -> any ProbeStore {
            switch kind {
            case "SwiftData": return try SwiftDataProbe(url: url, readOnly: readOnly)
            case "CoreData": return try CoreDataProbe(url: url, readOnly: readOnly)
            default: return try SQLiteProbe(url: url, readOnly: readOnly)
            }
        }
        var store: (any ProbeStore)? = try open()
        try store!.replace([sample])
        #expect(try store!.values() == [sample])
        store = nil
        store = try open()
        #expect(try store!.values().first!.body.utf8.elementsEqual(sample.body.utf8))
        var changed = sample; changed.body += "更新"; changed.revision = 2
        try store!.replace([changed])
        let reader = try open(true)
        #expect(try reader.values() == [changed])
        #expect(throws: (any Error).self) { try reader.replace([sample]) }
        #expect(try open().values() == [changed])
        try store!.replace([])
        #expect(try open().values().isEmpty)
        try record("crud-" + kind, ["result": "pass", "readOnlyWrite": "rejected", "scope": "independent connections in one process; writable parent directory"])
    }

    @Test func sqliteFTSAndIndex() throws {
        let db = try SQLiteProbe(url: directory().appending(path: "db"))
        try db.execute("CREATE VIRTUAL TABLE words USING fts5(body, tokenize='unicode61')")
        try db.execute("CREATE VIRTUAL TABLE tri USING fts5(body, tokenize='trigram')")
        for table in ["words", "tri"] { try db.execute("INSERT INTO \(table) VALUES('東京都に住む 日本語 👩🏽‍💻')") }
        var observed: [String: Int] = [:]
        for query in ["東", "東京", "東京都", "日本語", "京都"] {
            for table in ["words", "tri"] {
                observed[table + ":" + query] = try db.rows("SELECT rowid FROM \(table) WHERE \(table) MATCH '\(query)'").count
            }
        }
        #expect(observed["tri:東"] == 0 && observed["tri:東京"] == 0)
        #expect(observed["tri:東京都"] == 1)
        #expect(observed["words:東京"] == 0 && observed["words:日本語"] == 1)
        #expect(try db.rows("SELECT rowid FROM tri WHERE body LIKE '%東京%'").count == 1)
        try db.execute("UPDATE tri SET body='大阪府' WHERE rowid=1")
        #expect(try db.rows("SELECT rowid FROM tri WHERE tri MATCH '東京都'").isEmpty)
        #expect(try db.rows("SELECT rowid FROM tri WHERE tri MATCH '大阪府'").count == 1)
        try db.execute("DELETE FROM tri")
        #expect(try db.rows("SELECT rowid FROM tri WHERE tri MATCH '大阪府'").isEmpty)
        try db.execute("INSERT INTO tri(tri) VALUES('rebuild')")
        try record("fts", observed)
    }

    @Test func sqliteWALAndBackup() throws {
        let dir = try directory(), url = dir.appending(path: "db")
        let writer = try SQLiteProbe(url: url), reader = try SQLiteProbe(url: url, readOnly: true)
        try writer.replace([sample]); try reader.execute("BEGIN")
        #expect(try reader.values() == [sample])
        var edited = sample; edited.body = "新しい本文"
        try writer.replace([edited])
        #expect(try reader.values() == [sample])
        try reader.execute("COMMIT")
        #expect(try reader.values() == [edited])
        let second = try SQLiteProbe(url: url)
        try writer.execute("BEGIN IMMEDIATE")
        #expect(throws: (any Error).self) { try second.execute("BEGIN IMMEDIATE") }
        try writer.execute("DELETE FROM snippet"); try writer.execute("ROLLBACK")
        #expect(try reader.values() == [edited])
        let backup = try SQLiteProbe(url: dir.appending(path: "backup"))
        let handle = try #require(sqlite3_backup_init(backup.db, "main", writer.db, "main"))
        #expect(sqlite3_backup_step(handle, -1) == SQLITE_DONE)
        #expect(sqlite3_backup_finish(handle) == SQLITE_OK)
        #expect(try backup.values() == [edited])
        #expect(try backup.rows("PRAGMA integrity_check") == [["ok"]])
        // A copied database without its live WAL is not a backup.
        let unsafe = dir.appending(path: "main-only")
        try FileManager.default.copyItem(at: url, to: unsafe)
        let copied = try SQLiteProbe(url: unsafe, readOnly: true)
        let lostCommittedValue = (try? copied.values()) != [edited]
        #expect(lostCommittedValue)
        try record("wal", ["snapshotIsolation": true, "secondWriterRejected": true, "rollbackPreserved": true,
                           "onlineBackupExact": true, "mainFileOnlyLostCommittedValue": lostCommittedValue])
    }

    @Test func coreDataMigrationAndHistory() throws {
        let url = try directory().appending(path: "db")
        let old = try CoreDataProbe(url: url, withTitle: false)
        try old.replace([sample]); try old.close()
        let new = try CoreDataProbe(url: url)
        let migrated = try new.values()
        #expect(migrated.first?.id == sample.id && migrated.first?.body == sample.body && migrated.first?.title == "")
        try new.replace([sample])
        let result = try new.container.viewContext.execute(NSPersistentHistoryChangeRequest.fetchHistory(after: Date.distantPast)) as? NSPersistentHistoryResult
        let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []
        #expect(!transactions.isEmpty)
        try record("coredata-migration-history", ["transactions": transactions.count, "migratedRows": migrated.count])
    }

    @Test func swiftDataHistory() throws {
        let store = try SwiftDataProbe(url: directory().appending(path: "db"))
        try store.replace([sample])
        let history = try store.context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        #expect(!history.isEmpty)
        try store.replace([])
        let after = try store.context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        #expect(after.count > history.count)
        try record("swiftdata-history", ["beforeDelete": history.count, "afterDelete": after.count])
        let token = try #require(history.first?.token)
        try store.context.deleteHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        do {
            let remaining = try store.context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>(predicate: #Predicate { $0.token > token }))
            try record("history-purge", ["result": "accepted", "count": String(remaining.count)])
        } catch {
            try record("history-purge", ["result": "rejected", "error": String(describing: error)])
        }
        #expect(try store.values().isEmpty) // A full reload remains a recovery path.
    }

    @Test func swiftDataMigration() throws {
        let url = try directory().appending(path: "db")
        do {
            let schema = Schema(versionedSchema: OldSchema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container); context.insert(OldSchema.Item(id: sample.id, body: sample.body)); try context.save()
        }
        let schema = Schema(versionedSchema: NewSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: ProbeMigration.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let values = try ModelContext(container).fetch(FetchDescriptor<NewSchema.Item>())
        #expect(values.count == 1 && values[0].id == sample.id)
        #expect(values[0].body.utf8.elementsEqual(sample.body.utf8) && values[0].title == nil)
        try record("swiftdata-migration", ["rows": values.count, "version": 2])
    }

    @Test func atomicSnapshotAndProtectionAttribute() throws {
        let url = try directory().appending(path: "snapshot.json")
        let first = try JSONEncoder().encode(ProbeArchive(version: 1, values: [sample]))
        try first.write(to: url, options: [.atomic, .completeFileProtection])
        let oldReader = try FileHandle(forReadingFrom: url); defer { try? oldReader.close() }
        var updated = sample; updated.body = "次の版"
        let next = try JSONEncoder().encode(ProbeArchive(version: 1, values: [updated]))
        try next.write(to: url, options: [.atomic, .completeFileProtection])
        #expect(try oldReader.readToEnd() == first)
        #expect(try Data(contentsOf: url) == next)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        try record("snapshot", ["oldReader": "previous complete version", "newReader": "next complete version",
                                "protectionAttribute": String(describing: attrs[.protectionKey])])
    }

    @Test func invalidImportDoesNotChangeStore() throws {
        let store = try SwiftDataProbe(url: directory().appending(path: "db"))
        try store.replace([sample])
        do { try store.replace(ProbeArchive.decode(Data("{}".utf8))); Issue.record("Invalid import accepted") }
        catch { #expect(try store.values() == [sample]) }
    }

    @Test func failedSaveRetainsDraftAndRoutesRejectDestructiveInput() throws {
        let controller = ProbeController(); controller.loadViewIfNeeded(); controller.failSaves = true
        let navigation = UINavigationController(rootViewController: controller)
        controller.edit(sample)
        let editor = try #require(navigation.topViewController as? ProbeEditor); editor.loadViewIfNeeded()
        editor.name.text = sample.title; editor.input.text = sample.body + "下書き"; editor.keepDraft()
        defer { editor.clearDraft() }
        editor.onSave?(sample)
        #expect(editor.status.text?.hasPrefix("保存失敗") == true)
        #expect(editor.input.text == sample.body + "下書き")
        let reopened = ProbeEditor(value: sample); reopened.loadViewIfNeeded()
        #expect(reopened.input.text == editor.input.text)
        for invalid in ["nibble-probe://delete/123", "nibble-probe://create?body=hidden", "nibble-probe://list#hidden", "https://list", "nibble-probe://item/../list"] {
            #expect(ProbeRoute(URL(string: invalid)!) == nil)
        }
        #expect(ProbeRoute(URL(string: "nibble-probe://list")!) == .list)
        #expect(ProbeRoute(URL(string: "nibble-probe://create")!) == .create)
        try record("draft-and-route", ["failedSaveDraftRestored": true, "destructiveURLRejected": true])
    }

    @Test func archiveRoundTripAndValidation() throws {
        let data = try JSONEncoder().encode(ProbeArchive(version: 1, values: [sample]))
        let restored = try ProbeArchive.decode(data)
        #expect(restored.first!.body.utf8.elementsEqual(sample.body.utf8))
        for invalid in [Data("not-json".utf8), Data(repeating: 0, count: 4_000_001),
                        try JSONEncoder().encode(ProbeArchive(version: 2, values: [sample])),
                        try JSONEncoder().encode(ProbeArchive(version: 1, values: [sample, sample]))] {
            #expect(throws: (any Error).self) { try ProbeArchive.decode(invalid) }
        }
        try record("archive", ["roundtripExact": true, "invalidRejected": true])
    }

    @Test func normalizationCorpusAndMarkedText() throws {
        let pairs: [(String, String, Bool)] = [("か\u{3099}", "が", true), ("ｶﾞ", "ガ", true),
            ("ＡＢＣ", "abc", true), ("ガ", "が", false), ("が", "か", false),
            ("👩🏽‍💻", "👩🏽‍💻", true), ("_\"()", "_\"()", true)]
        var result: [String: Bool] = [:]
        for (source, query, expected) in pairs {
            let matched = SearchProbe.key(source).contains(SearchProbe.key(query))
            #expect(matched == expected)
            result[source + " → " + query] = matched
        }
        let text = UITextView(); text.text = sample.body
        #expect(text.text.utf8.elementsEqual(sample.body.utf8))
        text.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
        #expect(text.markedTextRange != nil)
        text.unmarkText(); #expect(text.markedTextRange == nil)
        try record("normalization", result)
    }

    @Test func staleSearchAndDatasetTiming() async throws {
        let search = SearchProbe()
        async let older: Void = search.search("古い", values: [sample], delay: .milliseconds(80))
        while search.generation == 0 { await Task.yield() }
        await search.search("定型", values: [sample], delay: .zero)
        await older
        #expect(search.ids == [sample.id])
        var timings: [String: [Double]] = [:]
        for count in [0, 20, 1_000, 10_000] {
            let values = (0..<count).map { ProbeValue(id: String($0), title: "定型文 \($0)", body: sample.body) }
            for kind in ["SwiftData", "CoreData", "SQLite"] {
                let url = try directory().appending(path: "db")
                let store: any ProbeStore
                switch kind {
                case "SwiftData": store = try SwiftDataProbe(url: url)
                case "CoreData": store = try CoreDataProbe(url: url)
                default: store = try SQLiteProbe(url: url)
                }
                let start = ContinuousClock.now
                try store.replace(values)
                let saved = ContinuousClock.now
                let loaded = try store.values()
                let fetched = ContinuousClock.now
                #expect(loaded.count == count)
                timings["\(kind)-\(count)-save-fetch-ms"] = [milliseconds(start.duration(to: saved)), milliseconds(saved.duration(to: fetched))]
            }
            var samples: [Double] = []
            for _ in 0..<30 {
                let start = ContinuousClock.now
                let matches = values.filter { SearchProbe.key($0.title + "\n" + $0.body).contains(SearchProbe.key("日本")) }
                #expect(matches.count == count)
                samples.append(milliseconds(start.duration(to: .now)))
            }
            timings["search-\(count)-ms"] = samples
        }
        try record("simulator-timing", timings)
    }

    func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components; return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15
    }

    @Test func pasteboardExpiration() async throws {
        let board = UIPasteboard.general
        board.setItems([["public.utf8-plain-text": "A"]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(1)])
        try await Task.sleep(for: .seconds(2))
        #expect(board.string == nil)
        var outcome: [String: Bool] = ["AExpired": board.string == nil]
        for replacement in ["B", "A"] {
            board.setItems([["public.utf8-plain-text": "A"]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(1)])
            board.setItems([["public.utf8-plain-text": replacement]], options: [.localOnly: true])
            try await Task.sleep(for: .seconds(2))
            #expect(board.string == replacement)
            outcome["replacement-" + replacement + "-survived"] = board.string == replacement
        }
        try record("pasteboard", outcome)
    }
}

enum OldSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Item.self] }
    @Model final class Item {
        var id: String
        var body: String
        init(id: String, body: String) { self.id = id; self.body = body }
    }
}
enum NewSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Item.self] }
    @Model final class Item {
        var id: String
        var body: String
        var title: String?
        init(id: String, body: String) { self.id = id; self.body = body }
    }
}
enum ProbeMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OldSchema.self, NewSchema.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: OldSchema.self, toVersion: NewSchema.self)] }
}
