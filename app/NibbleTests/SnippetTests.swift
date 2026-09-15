import Foundation
import UIKit
import SwiftUI
import Testing
import Tasking
import SQLite3
@testable import Nibble

private func location() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "NibbleTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "snippets.sqlite")
}

private func create(_ store: SnippetStore, title: String = "", body: String) async throws -> UUID {
    var draft = try await store.beginDraft(body: body)
    draft.title = title
    return try await store.save(draft)
}

@Suite("Snippet persistence and recovery")
struct SnippetTests {
    @Test func exactTextSurvivesReopenAndEdit() async throws {
        let url = try location()
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
        let store = SnippetStore(location: try location())
        let tokyo = try await create(store, title: "住所", body: "東京都 \n カナ ＡＢＣ か\u{3099} 100% _ \\")
        _ = try await create(store, body: "大阪府")
        for query in ["東", "東京", "住所", "ｶﾅ", "abc", "が", "%", "_", "\\"] {
            #expect(try await store.search(query).map(\.id) == [tokyo], "\(query)")
        }
        #expect(try await store.search("かな").isEmpty)
        #expect(try await store.search("存在しない").isEmpty)
    }

    @Test func deletionIsRecoverableAcrossLaunches() async throws {
        let url = try location()
        let store = SnippetStore(location: url)
        let id = try await create(store, body: "keep me")
        try await store.setDeleted(true, id: id)
        let reopened = SnippetStore(location: url)
        #expect(try await reopened.search().isEmpty)
        #expect(try await reopened.search(filter: .trash).map(\.id) == [id])
        try await reopened.setDeleted(false, id: id)
        #expect(try await store.search().map(\.id) == [id])
        await #expect(throws: StoreError.missing) { try await store.permanentlyDelete(id) }
        try await store.setDeleted(true, id: id)
        try await store.permanentlyDelete(id)
        await #expect(throws: StoreError.missing) { try await reopened.snippet(id) }
    }

    @Test func pinningAndPageLimits() async throws {
        let store = SnippetStore(location: try location())
        let pinned = try await create(store, body: "pinned")
        for number in 0..<12 { _ = try await create(store, body: "item \(number)") }
        try await store.setPinned(true, id: pinned)
        #expect(try await store.search(limit: 5).count == 5)
        #expect(try await store.search(limit: 5).first?.id == pinned)
        #expect(try await store.search(filter: .pinned).map(\.id) == [pinned])
    }

    @Test func concurrentEditorsNeverSilentlyOverwrite() async throws {
        let url = try location()
        let first = SnippetStore(location: url), second = SnippetStore(location: url)
        let id = try await create(first, body: "original")
        var a = try await first.beginDraft(snippetID: id)
        var b = try await second.beginDraft(snippetID: id)
        a.body = "first edit"; b.body = "second edit"; b.sequence = 1
        try await second.updateDraft(b)
        try await first.save(a)
        await #expect(throws: StoreError.conflict) { try await second.save(b) }
        #expect(try await first.snippet(id).body == "first edit")
        #expect(try await second.drafts().first?.body == "second edit")
        let recovered = try await second.save(b, asNew: true)
        #expect(recovered != id)
        #expect(try await first.snippet(recovered).body == "second edit")
    }

    @Test func draftOrderingAndLateWrites() async throws {
        let url = try location()
        let store = SnippetStore(location: url)
        var draft = try await store.beginDraft(body: "start")
        draft.sequence = 2; draft.body = "latest"
        try await store.updateDraft(draft)
        var old = draft; old.sequence = 1; old.body = "old"
        try await store.updateDraft(old)
        let reopened = SnippetStore(location: url)
        #expect(try await reopened.drafts().first?.body == "latest")
        try await store.save(draft)
        draft.sequence = 3
        try await store.updateDraft(draft)
        #expect(try await reopened.drafts().isEmpty)
        await #expect(throws: StoreError.missing) { try await store.save(draft) }
        #expect(try await reopened.search().count == 1)
    }

    @Test func validationFailureKeepsDraftAndExistingData() async throws {
        let store = SnippetStore(location: try location())
        let id = try await create(store, body: "original")
        var draft = try await store.beginDraft(snippetID: id)
        draft.body = " \n "; draft.sequence = 1
        try await store.updateDraft(draft)
        await #expect(throws: StoreError.empty) { try await store.save(draft) }
        #expect(try await store.snippet(id).body == "original")
        #expect(try await store.drafts().first?.id == draft.id)
        draft.body = String(repeating: "あ", count: 333_334)
        await #expect(throws: StoreError.tooLarge) { try await store.save(draft) }
    }

    @Test func parallelConnectionsKeepEveryInsert() async throws {
        let url = try location()
        let a = SnippetStore(location: url), b = SnippetStore(location: url)
        _ = try await a.search()
        try await withThrowingTaskGroup(of: UUID.self) { group in
            for number in 0..<30 {
                group.addTask { try await create(number.isMultiple(of: 2) ? a : b, body: "value \(number)") }
            }
            var ids = Set<UUID>()
            for try await id in group { ids.insert(id) }
            #expect(ids.count == 30)
        }
        #expect(try await a.search().count == 30)
        #expect(try await b.drafts().isEmpty)
    }

    @Test func unknownDatabaseVersionIsNotReplaced() async throws {
        let url = try location()
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
        let url = try location()
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
        let store = SnippetStore(location: try location())
        let id = try await create(store, body: "saved")
        let draft = try await store.beginDraft(snippetID: id)
        let editor = EditorModel(draft: draft, store: store)
        #expect(await editor.keepForLater())
        #expect(try await store.drafts().isEmpty)
        #expect(try await store.snippet(id).body == "saved")
    }

    @Test func simulatorSearchMeasurements() async throws {
        let store = SnippetStore(location: try location())
        let clock = ContinuousClock()
        var previousCount = 0
        var measurements: [[String: Any]] = []
        for count in [0, 20, 1_000, 10_000] {
            for number in previousCount..<count {
                _ = try await create(store, title: "定型文 \(number)", body: "  東京都の住所\nこんにちは。ご連絡ありがとうございます。 👩🏽‍💻  ")
            }
            previousCount = count
            for query in ["東", "見つからない語句"] {
                var values: [Double] = []
                for _ in 0..<30 {
                    let started = clock.now
                    let page = try await store.search(query)
                    let elapsed = started.duration(to: clock.now).components
                    values.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                    #expect(page.count == (query == "東" ? min(count, 100) : 0))
                }
                let sorted = values.sorted()
                measurements.append(["count": count, "query": query, "milliseconds": values,
                                     "median": (sorted[14] + sorted[15]) / 2, "max": sorted.last!])
            }
        }
        let directory = URL.documentsDirectory.appending(path: "results")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "mvp-search-timing.json"))
    }
}

@Suite("Owned UI actions", .serialized)
@MainActor
struct OwnedActionTests {
    @Test func backgroundDoesNotCancelTheSceneReload() async throws {
        let store = SnippetStore(location: try location())
        let id = try await create(store, body: "起動後も表示する本文")
        let library = LibraryModel(store: store)
        let owner = LibraryTaskOwner()
        owner.startTask(.refresh, on: library)
        // Transient presentation actions stop in background; an admitted scene read can finish.
        owner.endScreen()
        await owner.waitForIdle()
        #expect(library.items.map(\.id) == [id])
        #expect(!library.loading)
        #expect(library.error == nil)
    }

    @Test func repeatedOpenCreatesOnlyOneDraft() async throws {
        let store = SnippetStore(location: try location())
        let library = LibraryModel(store: store)
        let owner = LibraryTaskOwner()
        let first = owner.startTask(.open(nil), on: library)
        let duplicate = owner.startTask(.open(nil), on: library)
        #expect(first.run != nil)
        #expect(duplicate.skipReason == .alreadyRunning)
        await owner.waitForIdle()
        #expect(library.editor != nil)
        #expect(try await store.drafts().count == 1)
    }

    @Test func cancelledScreenOpenDoesNotBlockTheNextOpen() async throws {
        let store = SnippetStore(location: try location())
        let library = LibraryModel(store: store)
        let owner = LibraryTaskOwner()
        owner.startTask(.open(nil), on: library)
        owner.endScreen()
        await owner.waitForIdle()
        #expect(library.editor == nil)
        #expect(try await store.drafts().isEmpty)
        owner.startTask(.open(nil), on: library)
        await owner.waitForIdle()
        #expect(library.editor != nil)
        #expect(try await store.drafts().count == 1)
    }

    @Test func duplicatePolicyDoesNotDropActionsForDifferentItems() async throws {
        let store = SnippetStore(location: try location())
        _ = try await create(store, body: "first")
        _ = try await create(store, body: "second")
        let items = try await store.search()
        let library = LibraryModel(store: store)
        let owner = LibraryTaskOwner()
        owner.startTask(.pin(items[0]), on: library)
        owner.startTask(.pin(items[0]), on: library)
        owner.startTask(.pin(items[1]), on: library)
        await owner.waitForIdle()
        #expect(try await store.search(filter: .pinned).count == 2)
        #expect(library.error == nil)
    }

    @Test func rapidInputAndSaveKeepLatestTextWithoutResurrectingDraft() async throws {
        let store = SnippetStore(location: try location())
        let draft = try await store.beginDraft()
        let editor = EditorModel(draft: draft, store: store)
        for number in 0..<30 { editor.body = "日本語 \(number)" }
        #expect(await editor.save())
        let item = try #require(try await store.search().first)
        #expect(try await store.snippet(item.id).body == "日本語 29")
        #expect(try await store.drafts().isEmpty)
    }

    @Test func rapidInputCanResumeAfterClose() async throws {
        let url = try location()
        let store = SnippetStore(location: url)
        let draft = try await store.beginDraft()
        let editor = EditorModel(draft: draft, store: store)
        for number in 0..<30 { editor.body = "下書き \(number)" }
        #expect(await editor.keepForLater())
        let reopened = SnippetStore(location: url)
        #expect(try await reopened.drafts().first?.body == "下書き 29")
        #expect(try await reopened.search().isEmpty)
    }
}

@Suite("Awaitable operations", .serialized)
@MainActor
struct AwaitableOperationTests {
    @Test func directAwaitCompletesEachLibraryOperation() async throws {
        let store = SnippetStore(location: try location())
        let library = LibraryModel(store: store)
        await library.open()
        let draft = try #require(library.editor)
        let editor = EditorModel(draft: draft, store: store)
        editor.title = "直接待機"
        editor.body = "  日本語\n👩🏽‍💻  "
        #expect(await editor.save())
        await library.refresh()
        let item = try #require(library.items.first)
        await library.copy(item.id)
        #expect(UIPasteboard.general.string == editor.body)
        #expect(library.notice == "コピーしました") // Copy does not wait for notice expiry.
        await library.pin(item)
        #expect(library.items.first?.pinned == true)
        await library.delete(item.id)
        #expect(library.items.isEmpty)
        #expect(library.undoID == item.id)
        await library.restore(item.id)
        #expect(library.items.first?.id == item.id)
        await library.delete(item.id)
        await library.permanentlyDelete(item.id)
        #expect(try await store.search(filter: .trash).isEmpty)
        #expect(library.error == nil)
    }

    @Test func settersOnlyChangeMemoryAndPersistenceIsAwaitable() async throws {
        let store = SnippetStore(location: try location())
        let editor = EditorModel(draft: try await store.beginDraft(), store: store)
        editor.body = "最初"
        let older = editor.draft
        editor.body = "最新"
        let newest = editor.draft
        #expect(try await store.drafts().first?.body == "")
        await editor.persist(newest)
        await editor.persist(older)
        #expect(try await store.drafts().first?.body == "最新")
    }

    @Test func admittedAutosaveAndImmediateSaveCannotResurrectDraft() async throws {
        let store = SnippetStore(location: try location())
        let editor = EditorModel(draft: try await store.beginDraft(), store: store)
        editor.body = "途中"
        let snapshot = editor.draft
        async let autosave: Void = editor.persist(snapshot)
        editor.body = "保存する最新値"
        #expect(await editor.save())
        await autosave
        await editor.persist(snapshot)
        #expect(try await store.drafts().isEmpty)
        let item = try #require(try await store.search().first)
        #expect(try await store.snippet(item.id).body == "保存する最新値")
    }

    @Test func discardCompletesAndRejectsLateAutosave() async throws {
        let store = SnippetStore(location: try location())
        let editor = EditorModel(draft: try await store.beginDraft(), store: store)
        editor.body = "破棄する入力"
        let snapshot = editor.draft
        async let autosave: Void = editor.persist(snapshot)
        #expect(await editor.discard())
        await autosave
        await editor.persist(snapshot)
        #expect(try await store.drafts().isEmpty)
        #expect(try await store.search().isEmpty)
    }

    @Test func cancelledCallerCannotBeginAnOperation() async throws {
        let store = SnippetStore(location: try location())
        let id = try await create(store, body: "維持する本文")
        let library = LibraryModel(store: store)
        // Cancel synchronously before the MainActor operation can start. The
        // closure still calls the model, so the model's own contract is tested.
        let tasks = ViewTaskStore()
        tasks.start(id: "cancelled.operations", lifetime: .screenBound) { _ in
            await library.open()
            await library.delete(id)
            await library.copy(id)
        }
        tasks.cancelAll()
        await tasks.waitForIdle()
        #expect(library.editor == nil)
        #expect(library.notice == nil)
        #expect(library.feedback == 0)
        #expect(try await store.drafts().isEmpty)
        #expect(try await store.snippet(id).deleted == false)
    }

    @Test func supersededRefreshPublishesTheLatestQuery() async throws {
        let store = SnippetStore(location: try location())
        _ = try await create(store, body: "first")
        let last = try await create(store, body: "second")
        let library = LibraryModel(store: store)
        let owner = LibraryTaskOwner()
        library.query = "first"
        owner.startTask(.refresh, on: library)
        library.query = "second"
        owner.startTask(.refresh, on: library)
        await owner.waitForIdle()
        #expect(library.items.map(\.id) == [last])
        #expect(!library.loading)
    }

    @Test func noticeExpiryIsSeparateAndCancellationPreservesNotice() async throws {
        let store = SnippetStore(location: try location())
        let id = try await create(store, body: "copy")
        let library = LibraryModel(store: store)
        await library.copy(id)
        let first = try #require(library.noticeID)
        let tasks = ViewTaskStore()
        tasks.start(id: "notice.expiry", lifetime: .screenBound) { _ in
            await library.expireNotice(id: first)
        }
        tasks.cancelAll()
        await tasks.waitForIdle()
        #expect(library.noticeID == first)
        await library.copy(id)
        #expect(library.noticeID != first)
        // A stale ID is ignored without clearing the replacement notice.
        await library.expireNotice(id: first)
        #expect(library.notice != nil)
        await library.expireNotice(id: try #require(library.noticeID))
        #expect(library.notice == nil)
        #expect(library.undoID == nil)
    }
}

@Suite("AppMacros row comparison", .serialized)
@MainActor
struct RowComparisonTests {
    @Test func everyDisplayedInputParticipatesInEquality() {
        let row = SnippetRowContent(title: "返信", preview: "確認します", pinned: false)
        #expect(row == SnippetRowContent(title: "返信", preview: "確認します", pinned: false))
        #expect(row != SnippetRowContent(title: "予定", preview: "確認します", pinned: false))
        #expect(row != SnippetRowContent(title: "返信", preview: "明日確認します", pinned: false))
        #expect(row != SnippetRowContent(title: "返信", preview: "確認します", pinned: true))
        // A body-derived heading must also invalidate when its preview changes.
        #expect(SnippetRowContent(title: "", preview: "一件目", pinned: false)
                != SnippetRowContent(title: "", preview: "二件目", pinned: false))
    }

    @Test func mountedRowUpdatesAndReturnsToTheSamePixels() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = SnippetRowContent(title: "返信", preview: "確認します", pinned: false)
        let host = UIHostingController(rootView: original)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        func pixels() throws -> Data {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format)
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            return try #require(image.pngData())
        }

        // Await the mounted hierarchy's render pass; no task is created inside the helper.
        func render(_ row: SnippetRowContent) async throws -> Data {
            host.rootView = row
            try await Task.sleep(for: .milliseconds(100))
            return try pixels()
        }

        let initial = try await render(original)
        for row in [
            SnippetRowContent(title: "予定", preview: "確認します", pinned: false),
            SnippetRowContent(title: "返信", preview: "明日確認します", pinned: false),
            SnippetRowContent(title: "返信", preview: "確認します", pinned: true),
            SnippetRowContent(title: "", preview: "本文から見出し", pinned: false),
        ] {
            let updated = try await render(row)
            #expect(updated != initial)
            let restored = try await render(original)
            #expect(restored == initial)
        }
    }
}
