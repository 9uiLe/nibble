import Foundation
import Testing
import SQLite3
@testable import Nibble

@Suite("Snippet persistence and recovery")
struct SnippetTests {
    @Test func featureAvailabilityMatchesTheConfiguredAudience() {
        #expect(FeatureAccess.availability(.variableReplacement, pro: false) == .included)
        let subscription = FeaturePolicy(proFeatures: [.variableReplacement], subscriptionsOffered: true)
        #expect(subscription.availability(.variableReplacement, pro: false) == .requiresPro)
        #expect(subscription.availability(.variableReplacement, pro: true) == .included)
        let withheld = FeaturePolicy(proFeatures: [.variableReplacement], subscriptionsOffered: false)
        #expect(withheld.availability(.variableReplacement, pro: false) == .unavailable)
    }

    @Test func variableValuesReplaceEachOccurrenceWithoutEditingOriginal() {
        #expect(SnippetVariables.marker(for: "宛名") == "{{宛名}}")
        #expect(SnippetVariables.marker(for: "") == nil)
        let original = "{{宛名}}さん\r\n{{宛名}}へ 👩🏽‍💻 {{日付}} / {{ }} / {{未完"
        let template = SnippetVariables(original)
        #expect(template.names == ["宛名", "日付"])
        #expect(template.filled(with: ["宛名": "山田", "日付": "9月24日"]) ==
            "山田さん\r\n山田へ 👩🏽‍💻 9月24日 / {{ }} / {{未完")
        #expect(template.filled(with: ["宛名": "山田"]) == nil)
        #expect(template.body.utf8.elementsEqual(original.utf8))
        #expect(SnippetVariables("普通の本文").filled(with: [:]) == "普通の本文")
    }

    @Test func largeVariableBodyKeepsEveryByteOutsideMarkers() {
        let text = String(repeating: "本文👩🏽‍💻\r\n", count: 40_000)
        let original = "先頭{{ 宛名 }}" + text + "{{宛名}}末尾"
        let template = SnippetVariables(original)
        #expect(template.names == ["宛名"])
        #expect(template.filled(with: ["宛名": "山田"]) == "先頭山田" + text + "山田末尾")
        #expect(template.body == original)
    }

    @Test func savingHasNoPlanBasedCountLimitAndPreservesDraftsAndExistingUse() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let free = SnippetStore(location: database.url)
        var ids: [UUID] = []
        for number in 0..<31 {
            ids.append(try await create(free, body: "item \(number)"))
        }
        var draft = try await free.beginDraft(body: "next item")
        draft.title = "continued"
        try await free.save(draft)
        var edit = try await free.editingDraft(for: ids[0])
        edit.body = "edited"
        try await free.save(edit)
        #expect(try await free.savedBody(ids[0]) == "edited")
        try await free.mutate(.delete, id: ids[0])
        try await free.mutate(.restore, id: ids[0])
        let overflow = try await free.beginDraft(body: "overflow")
        try await free.save(overflow)
        #expect(try await free.search().count == 33)
    }

    @Test func exactTextSurvivesReopenAndEdit() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let store = SnippetStore(location: url)
        let text = "  日本語 か\u{3099}\n\t👩🏽‍💻 <code>\0tail  "
        let id = try await create(store, title: "  住所  ", body: text)
        let reopened = SnippetStore(location: url)
        let value = try await reopened.snippet(id)
        #expect(Array(value.body.utf8) == Array(text.utf8))
        #expect(value.title == "  住所  ")
        var draft = try await reopened.beginDraft(snippetID: id)
        draft.body += "改訂"
        try await reopened.save(draft)
        #expect(try await store.snippet(id).body == text + "改訂")
    }

    @Test func shortJapaneseAndLiteralSearch() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let tokyo = try await create(store, title: "住所", body: "東京都 \n カナ ＡＢＣ か\u{3099} 100% _ \\")
        _ = try await create(store, body: "大阪府")
        for query in ["東", "東京", "住所", "ｶﾅ", "abc", "が", "%", "_", "\\"] {
            #expect(try await store.search(query).map(\.id) == [tokyo], "\(query)")
        }
        #expect(try await store.search("かな").isEmpty)
        #expect(try await store.search("存在しない").isEmpty)
    }

    @Test func deletionIsRecoverableAcrossLaunches() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let store = SnippetStore(location: url)
        let id = try await create(store, body: "keep me")
        try await store.mutate(.delete, id: id)
        let reopened = SnippetStore(location: url)
        #expect(try await reopened.search().isEmpty)
        #expect(try await reopened.search(filter: .trash).map(\.id) == [id])
        try await reopened.mutate(.restore, id: id)
        #expect(try await store.search().map(\.id) == [id])
        let draft = try await store.editingDraft(for: id)
        await #expect(throws: StoreError.missing) { try await store.mutate(.permanentlyDelete, id: id) }
        #expect(try await store.snippet(id).body == "keep me")
        #expect(try await store.draft(draft.id).snippetID == id)
        try await store.mutate(.delete, id: id)
        try await store.mutate(.permanentlyDelete, id: id)
        await #expect(throws: StoreError.missing) { try await reopened.snippet(id) }
        await #expect(throws: StoreError.missing) { try await reopened.draft(draft.id) }
    }

    @Test func concurrentEditorsNeverSilentlyOverwrite() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let first = SnippetStore(location: url), second = SnippetStore(location: url)
        let id = try await create(first, body: "original")
        var a = try await first.beginDraft(snippetID: id)
        var b = try await second.beginDraft(snippetID: id)
        a.body = "first edit"; b.body = "second edit"
        try await second.updateDraft(b)
        try await first.save(a)
        await #expect(throws: StoreError.conflict) { try await second.save(b) }
        #expect(try await first.snippet(id).body == "first edit")
        #expect(try await second.draft(b.id).body == "second edit")
        let recovered = try await second.save(b, asNew: true)
        #expect(recovered != id)
        #expect(try await first.snippet(recovered).body == "second edit")
    }

    @Test func draftOrderingAndLateWrites() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let store = SnippetStore(location: url)
        var draft = try await store.beginDraft(body: "start")
        draft.body = "old"
        let old = draft
        draft.body = "latest"
        try await store.updateDraft(draft)
        try await store.updateDraft(old)
        let reopened = SnippetStore(location: url)
        #expect(try await reopened.draft(draft.id).body == "latest")
        try await store.save(draft)
        draft.body = "late"
        try await store.updateDraft(draft)
        #expect(try await reopened.drafts().isEmpty)
        await #expect(throws: StoreError.missing) { try await store.save(draft) }
        #expect(try await reopened.search().count == 1)
    }

    @Test func validationFailureKeepsDraftAndExistingData() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let id = try await create(store, body: "original")
        var draft = try await store.beginDraft(snippetID: id)
        draft.body = " \n "
        try await store.updateDraft(draft)
        await #expect(throws: StoreError.empty) { try await store.save(draft) }
        #expect(try await store.snippet(id).body == "original")
        #expect(try await store.drafts().first?.id == draft.id)
        draft.body = String(repeating: "あ", count: 333_333) + "a"
        draft.title = String(repeating: "あ", count: 170) + "ab"
        try await store.save(draft) // Exact UTF-8 limits, not character counts.
        let atLimit = try await store.beginDraft(snippetID: id)
        var tooLong = atLimit
        tooLong.title += "a"
        await #expect(throws: StoreError.tooLarge) { try await store.save(tooLong) }
        tooLong = atLimit
        tooLong.body += "a"
        await #expect(throws: StoreError.tooLarge) { try await store.save(tooLong) }
        #expect(try await store.snippet(id).body.utf8.count == 1_000_000)
        #expect(try await store.draft(atLimit.id).title.utf8.count == 512)
    }

    @Test func parallelConnectionsKeepEveryInsert() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let a = SnippetStore(location: url), b = SnippetStore(location: url)
        _ = try await a.search()
        try await withThrowingTaskGroup(of: UUID.self) { group in
            for number in 0..<4 {
                group.addTask { try await create(number.isMultiple(of: 2) ? a : b, body: "value \(number)") }
            }
            var ids = Set<UUID>()
            for try await id in group { ids.insert(id) }
            #expect(ids.count == 4)
        }
        #expect(try await a.search().count == 4)
        #expect(try await b.drafts().isEmpty)
    }

    @Test func unknownDatabaseVersionIsNotReplaced() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let before = try Data(contentsOf: url)
        let store = SnippetStore(location: url)
        await #expect(throws: StoreError.newerVersion) { try await store.search() }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func corruptDatabaseIsNotReinitialized() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let url = database.url
        let data = Data(repeating: 0xFF, count: 4096)
        try data.write(to: url)
        let store = SnippetStore(location: url)
        await #expect(throws: StoreError.database) { try await store.search() }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func deepLinksOnlyNavigate() {
        #expect(AppRoute(url: URL(string: "nibble://library")!) == .library)
        #expect(AppRoute(url: URL(string: "nibble://new")!) == .create)
        for value in ["nibble://delete", "nibble://new?body=secret", "nibble://library/#secret", "nibble://user@new", "https://new", "nibble://new/anything"] {
            #expect(AppRoute(url: URL(string: value)!) == nil)
        }
    }

    @Test @MainActor func closingAnUnchangedEditorDoesNotLeaveADraft() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let id = try await create(store, body: "saved")
        let draft = try await store.beginDraft(snippetID: id)
        let editor = EditorModel(draft: draft, store: store)
        #expect(await editor.finish(.keep))
        #expect(try await store.drafts().isEmpty)
        #expect(try await store.snippet(id).body == "saved")
    }
}
