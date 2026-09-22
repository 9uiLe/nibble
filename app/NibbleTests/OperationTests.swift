import Foundation
import UIKit
import Testing
import Tasking
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Awaitable operations", .serialized)
    @MainActor
    struct AwaitableOperationTests {
        @Test func directAwaitCopiesSavedTextToTheSystemPasteboard() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let library = LibraryModel(store: store, effects: SystemLibraryEffects())
            await library.open()
            let draft = try #require(library.editor)
            let editor = EditorModel(draft: draft, store: store)
            editor.title = "直接待機"
            editor.body = "  日本語\n👩🏽‍💻  "
            #expect(await editor.finish(.save))
            library.editor = nil
            library.setNoticePresentation(true)
            await library.refresh()
            let item = try #require(library.items.first)
            await library.copy(item.id)
            #expect(UIPasteboard.general.string == editor.body)
            #expect(library.notice?.message == "コピーしました") // Copy does not wait for notice expiry.
        }

        @Test func librarySectionsKeepSearchIndependentAndRefreshSharedChanges() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let first = try await create(store, body: "定型文")
            let second = try await create(store, body: "検索だけに一致")
            try await store.setPinned(true, id: first)
            let all = LibraryModel(store: store)
            let search = LibraryModel(store: store, surface: .search)
            let deleted = LibraryModel(store: store, surface: .deleted)
            search.filter = .drafts
            deleted.filter = .all
            #expect(search.filter == .all && deleted.filter == .trash)
            #expect(search.refreshOnAppearance && deleted.refreshOnAppearance)
            search.query = "検索だけ"
            search.showMore()
            await all.refresh()
            await search.refresh()
            #expect(Set(all.items.map(\.id)) == [first, second])
            #expect(all.items.filter(\.pinned).map(\.id) == [first])
            #expect(search.items.map(\.id) == [second])
            #expect(all.query.isEmpty)
            #expect(all.request.limit == LibraryRequest.pageSize)
            let item = try #require(all.items.first { $0.id == first })
            await all.pin(item)
            #expect(all.items.allSatisfy { !$0.pinned })
            await all.delete(second)
            await search.refresh()
            #expect(search.items.isEmpty)
            #expect(search.query == "検索だけ")
        }

        @Test func libraryFiltersSeparateSavedPinnedAndDraftContent() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let pinned = try await create(store, body: "よく使う本文")
            let other = try await create(store, body: "保存済み")
            let deleted = try await create(store, body: "削除した本文")
            try await store.setPinned(true, id: pinned)
            try await store.mutate(.delete, id: deleted)
            let draft = try await store.beginDraft(body: "  未保存\n👩🏽‍💻  ")
            let all = try await store.library(LibraryRequest())
            #expect(Set(all.items.map(\.id)) == [pinned, other])
            #expect(all.drafts.map(\.id) == [draft.id])
            #expect(all.counts == LibraryCounts(saved: 2, pinned: 1, drafts: 1))
            let pins = try await store.library(LibraryRequest(filter: .pinned, limit: 1))
            #expect(pins.items.map(\.id) == [pinned])
            #expect(pins.drafts.isEmpty && !pins.hasMore)
            let missing = try await store.library(LibraryRequest(query: "なし", limit: 1))
            #expect(missing.items.isEmpty && !missing.hasMore)
            let drafts = try await store.library(LibraryRequest(filter: .drafts, limit: 1))
            #expect(drafts.items.isEmpty && !drafts.hasMore)
            #expect(drafts.drafts.map(\.id) == [draft.id])
            let trash = try await store.library(LibraryRequest(filter: .trash))
            #expect(trash.items.map(\.id) == [deleted] && trash.drafts.isEmpty)
            for page in [pins, missing, drafts, trash] {
                #expect(page.counts == all.counts)
            }
            let limited = try await store.library(LibraryRequest(limit: 1))
            #expect(limited.items.count == 1 && limited.hasMore)
            #expect(limited.counts == all.counts)
            #expect(try await store.search(filter: .drafts).isEmpty)
            let model = LibraryModel(store: store)
            model.filter = .drafts
            await model.open(.draft(draft.id))
            let resumed = try #require(model.editor)
            #expect(resumed.id == draft.id && resumed.body == draft.body)
            _ = try await store.save(resumed)
            await model.refresh()
            #expect(model.drafts.isEmpty && model.items.isEmpty && model.filter == .drafts)
            model.filter = .all
            await model.refresh()
            #expect(model.items.count == 3)
        }

        @Test func changedQueryRetainsContentUntilTheMatchingReadCompletes() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let saved = try await create(database.store, body: "検索対象")
            let model = LibraryModel(store: database.store, surface: .search)
            await model.refresh()
            model.showMore()
            model.query = ""
            #expect(model.request.limit == 200)
            model.query = "一致しない語句"
            #expect(model.loading && !model.contentIsCurrent && model.items.map(\.id) == [saved])
            #expect(model.request.limit == 100)
            await model.refresh()
            #expect(!model.loading && model.items.isEmpty && model.contentIsCurrent)
            model.query = "か\u{3099}"
            await model.refresh()
            model.query = "が"
            #expect(model.contentIsCurrent && !model.loading)
        }

        @Test func retainedFiltersSwitchImmediatelyAndRefreshAllCollections() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let pinned = try await create(store, body: "ピン留めの原文")
            try await store.setPinned(true, id: pinned)
            let draft = try await store.beginDraft(body: "未保存の原文")
            let model = LibraryModel(store: store, effects: RecordingLibraryEffects())
            model.query = "ignored"
            model.filter = .trash
            #expect(model.query.isEmpty && model.filter == .all && model.refreshOnAppearance)
            await model.refresh()
            #expect(!model.refreshOnAppearance && model.readDemand == nil)
            model.filter = .drafts
            #expect(!model.loading && model.contentIsCurrent && model.readDemand == nil && model.drafts.map(\.id) == [draft.id])
            model.filter = .pinned
            #expect(!model.loading && model.items.map(\.id) == [pinned])
            // External writes remain invisible until the user's pull to refresh.
            let external = try await create(store, body: "共有拡張で保存")
            model.filter = .all
            #expect(!model.loading && model.items.map(\.id) == [pinned])
            await model.reload()
            #expect(Set(model.items.map(\.id)) == [pinned, external])
            let item = try #require(model.items.first { $0.id == external })
            await model.pin(item)
            model.filter = .pinned
            #expect(!model.loading && Set(model.items.map(\.id)) == [pinned, external])
            await model.delete(pinned)
            model.filter = .all
            #expect(model.items.map(\.id) == [external])
            model.filter = .drafts
            #expect(!model.loading && model.drafts.map(\.id) == [draft.id])
        }

        @Test func retainedBatchFollowsSelectionAndDoesNotPublishPartialFailure() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let reader = ControlledLibraryReader()
            let model = LibraryModel(store: database.store, effects: RecordingLibraryEffects(),
                                     libraryReader: reader)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            #expect(reader.requests[0].map(\.filter) == [.all, .pinned, .drafts])
            model.filter = .pinned
            reader.finish(0, with: .success(LibraryPage(counts: LibraryCounts(saved: 2, pinned: 1))))
            await owner.waitForIdle()
            #expect(!model.loading && model.contentRequest.filter == .pinned && model.page.counts.saved == 2)
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            model.filter = .drafts
            reader.finish(1, with: .failure(StoreError.unavailable))
            await owner.waitForIdle()
            #expect(!model.loading && model.failure != nil && model.page.counts.saved == 2)
            model.filter = .all
            #expect(!model.loading && model.contentIsCurrent && model.page.counts.saved == 2)
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(3)
            reader.finishBatch(2, with: .success([LibraryPage(counts: LibraryCounts(saved: 99))]))
            await owner.waitForIdle()
            #expect(model.failure != nil && model.page.counts.saved == 2)
            model.filter = .pinned
            #expect(model.page.counts.saved == 2 && model.readDemand == nil)
        }

        @Test func retainedPagesPreserveIndependentLimitsAndEveryOrderedItem() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            _ = try await store.search()
            let db = try SQLiteDatabase(url: database.url)
            let ids = (1...201).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
            try db.writeTransaction {
                for id in ids {
                    try db.execute("INSERT INTO snippets(id,title,body,search_key,pinned,revision,updated,deleted) VALUES(?,'項目','本文','本文',?,1,1000,0)",
                                   [.text(id.uuidString), .int(id == ids.last ? 1 : 0)])
                }
            }
            let model = LibraryModel(store: store, effects: RecordingLibraryEffects())
            await model.refresh()
            #expect(model.items.map(\.id) == Array(ids.prefix(100)) && model.hasMore)
            model.filter = .pinned
            #expect(model.items.map(\.id) == [ids.last!] && !model.loading && model.readDemand == nil)
            model.filter = .all
            model.showMore()
            await model.refresh()
            #expect(model.items.map(\.id) == Array(ids.prefix(200)) && model.hasMore)
            model.showMore()
            await model.refresh()
            #expect(model.items.map(\.id) == ids && !model.hasMore)
            model.filter = .pinned
            #expect(model.request.limit == 100 && model.items.map(\.id) == [ids.last!])
            model.filter = .all
            #expect(model.request.limit == 300 && model.items.map(\.id) == ids && model.readDemand == nil)
        }

        @Test(arguments: [false, true])
        func staleReadCannotFinishTheNextSelection(fails: Bool) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let reader = ControlledLibraryReader()
            let model = LibraryModel(store: database.store, surface: .search, libraryReader: reader)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            reader.finish(0, with: .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(!model.loading)

            model.query = "draft"
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            // The next onChange has not started its task when the old read finishes.
            model.query = "all"
            reader.finish(1, with: fails ? .failure(StoreError.unavailable) : .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(model.loading && model.failure == nil)
            #expect(model.contentRequest.query.isEmpty && !model.contentIsCurrent)

            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(3)
            reader.finish(2, with: .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(!model.loading && model.contentIsCurrent && model.failure == nil)
            #expect(model.contentRequest.query == "all")
        }

        @Test func lateReadCannotReplaceTheLatestResult() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let reader = ControlledLibraryReader()
            let model = LibraryModel(store: database.store, surface: .search, libraryReader: reader)
            let olderOwner = LibraryTaskOwner()
            let latestOwner = LibraryTaskOwner()
            olderOwner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            model.query = "draft"
            latestOwner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            reader.finish(1, with: .success(LibraryPage()))
            await latestOwner.waitForIdle()
            #expect(!model.loading && model.contentRequest.query == "draft")
            reader.finish(0, with: .failure(StoreError.unavailable))
            await olderOwner.waitForIdle()
            #expect(!model.loading && model.failure == nil && model.contentIsCurrent)
            #expect(model.contentRequest.query == "draft")
        }

        @Test func failedQueryReadDoesNotBecomeAnEmptyResultOrLeakIntoAnotherQuery() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let reader = ControlledLibraryReader()
            let model = LibraryModel(store: database.store, surface: .search, libraryReader: reader)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            reader.finish(0, with: .failure(StoreError.unavailable))
            await owner.waitForIdle()
            #expect(!model.loading && !model.contentIsCurrent && model.failure != nil)
            model.query = "draft"
            #expect(model.loading && model.failure == nil && !model.contentIsCurrent)
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            reader.finish(1, with: .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(!model.loading && model.contentIsCurrent && model.drafts.isEmpty)
            model.showMore()
            #expect(model.loading && model.contentIsCurrent)
            #expect(model.contentRequest.limit == LibraryRequest.pageSize)
        }

        @Test(arguments: [LibraryFilter.pinned, .drafts])
        func creatingKeepsTheSelectedCollection(filter: LibraryFilter) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = LibraryModel(store: database.store)
            await model.refresh()
            model.filter = filter
            await model.open(.new)
            let draft = try #require(model.editor)
            #expect(model.filter == filter && model.readDemand == nil)
            model.editor = nil
            await model.refresh()
            #expect(model.filter == filter)
            model.filter = .drafts
            #expect(model.drafts.map(\.id) == [draft.id])
        }

        @Test func settersOnlyChangeMemoryAndPersistenceIsAwaitable() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let editor = EditorModel(draft: try await store.beginDraft(), store: store)
            editor.body = "最初"
            let older = editor.draft
            editor.body = "最新"
            let newest = editor.draft
            #expect(try await store.draft(editor.draft.id).body == "")
            await editor.persist(newest)
            await editor.persist(older)
            #expect(try await store.draft(editor.draft.id).body == "最新")
        }

        @Test(arguments: [EditorModel.FinishOperation.save, .discard])
        func finishingRejectsAdmittedAndLateAutosaves(operation: EditorModel.FinishOperation) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let storage = PausedDraftEditing(store: store)
            let editor = EditorModel(draft: try await store.beginDraft(), store: storage)
            editor.body = "途中"
            let snapshot = editor.draft
            async let autosave: Void = editor.persist(snapshot)
            await storage.waitForUpdate()
            editor.body = "保存する最新値"
            #expect(await editor.finish(operation))
            storage.resumeUpdate()
            await autosave
            await editor.persist(snapshot)
            #expect(try await store.drafts().isEmpty)
            let items = try await store.search()
            if operation == .save {
                #expect(items.count == 1)
                let item = try #require(items.first)
                #expect(try await store.snippet(item.id).body == "保存する最新値")
            } else {
                #expect(items.isEmpty)
            }
        }

        @Test(arguments: [false, true])
        func cancelledReadSettlesWithoutReportingAnError(providerFails: Bool) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let reader = ControlledLibraryReader()
            let library = LibraryModel(store: database.store, libraryReader: reader)
            let tasks = ViewTaskStore()
            tasks.start(id: "read", lifetime: .screenBound) { _ in await library.refresh() }
            await reader.waitForRequests(1)
            tasks.cancelAll()
            reader.finish(0, with: providerFails ? .failure(StoreError.missing) : .success(LibraryPage()))
            await tasks.waitForIdle()
            #expect(!library.loading)
            #expect(library.failure == nil)
            #expect(library.snapshot == nil)
            #expect(library.loadingInterrupted)
            tasks.start(id: "read", lifetime: .screenBound) { _ in await library.refresh() }
            await reader.waitForRequests(2)
            #expect(library.loading && !library.loadingInterrupted)
            reader.finish(1, with: .success(LibraryPage()))
            await tasks.waitForIdle()
            #expect(library.contentIsCurrent && !library.loading && !library.loadingInterrupted)
            #expect(library.failure == nil)
        }

        @Test func cancelledQueryReadRetainsThePreviousSnapshotUntilRetry() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let id = try await create(database.store, body: "前の表示")
            let page = try await database.store.library(LibraryRequest())
            let reader = ControlledLibraryReader()
            let library = LibraryModel(store: database.store, surface: .search, libraryReader: reader)
            let tasks = ViewTaskStore()
            tasks.start(id: "read", lifetime: .screenBound) { _ in await library.refresh() }
            await reader.waitForRequests(1)
            reader.finish(0, with: .success(page))
            await tasks.waitForIdle()
            library.query = "見つからない"
            tasks.start(id: "read", lifetime: .screenBound) { _ in await library.refresh() }
            await reader.waitForRequests(2)
            tasks.cancelAll()
            reader.finish(1, with: .success(LibraryPage()))
            await tasks.waitForIdle()
            #expect(library.items.map(\.id) == [id])
            #expect(library.contentRequest.query.isEmpty && library.query == "見つからない")
            #expect(!library.contentIsCurrent && library.loadingInterrupted && !library.loading)
            tasks.start(id: "read", lifetime: .screenBound) { _ in await library.refresh() }
            await reader.waitForRequests(3)
            reader.finish(2, with: .success(LibraryPage()))
            await tasks.waitForIdle()
            #expect(library.contentIsCurrent && library.items.isEmpty && !library.loadingInterrupted)
        }

        @Test func cancelledCallerCannotBeginAnOperation() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
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
            #expect(try await store.snippet(id).usage.count == 0)
            #expect(try await store.drafts().isEmpty)
            #expect(try await store.snippet(id).deleted == false)
        }

        @Test func emptySearchPreservesOperationFailureUntilExplicitRecovery() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let library = LibraryModel(store: database.store, surface: .search)
            library.query = "  "
            await library.copy(UUID())
            let failure = try #require(library.failure)
            #expect(failure.title == "コピーできませんでした")
            #expect(failure.recovery == .reload)
            await library.refresh()
            #expect(library.failure == failure)
            #expect(library.query == "  " && !library.loading)
            let feedback = library.feedback
            await library.reload()
            #expect(library.failure == nil && library.notice == nil)
            #expect(library.feedback == feedback) // Reload never retries a clipboard operation.
            #expect(library.query == "  ")
        }

        @Test func loadingFailureIsSeparateFromFailedCreation() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let directory = database.url.deletingLastPathComponent()
            let file = directory.appending(path: "not-a-directory")
            try Data([1]).write(to: file)
            let effects = RecordingLibraryEffects()
            let library = LibraryModel(store: SnippetStore(location: file.appending(path: "db.sqlite")), effects: effects)
            await library.refresh()
            #expect(library.failure?.title == "一覧を読み込めませんでした")
            #expect(library.failure?.recovery == .reload)
            await library.open()
            #expect(library.failure?.title == "編集を始められませんでした")
            #expect(library.editor == nil)
            #expect(effects.events.isEmpty)
            library.dismissFailure()
            #expect(library.failure?.title == "一覧を読み込めませんでした")
            try FileManager.default.removeItem(at: file)
            await library.reload()
            #expect(library.failure == nil && !library.loading)
        }

        @Test func editorExplainsRequiredBodyWithoutChangingOriginalInput() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let draft = try await database.store.beginDraft()
            let editor = EditorModel(draft: draft, store: database.store)
            editor.title = "名前だけ"
            for body in ["", " \n\t"] {
                editor.body = body
                #expect(!editor.hasBody && !editor.canSave)
                #expect(editor.body.utf8.elementsEqual(body.utf8))
            }
            let original = "  原文\n👩🏽‍💻  "
            editor.body = "途中の入力"
            editor.body = original
            #expect(editor.hasBody && editor.canSave)
            #expect(await editor.finish(.keep))
            let reopened = SnippetStore(location: database.url)
            #expect(try await reopened.draft(draft.id).body.utf8.elementsEqual(original.utf8))
            #expect(try await reopened.search().isEmpty)
        }

    }
}

/// Explicit completion gates reproduce request ordering without sleeps or scheduler assumptions.
@MainActor
private final class ControlledLibraryReader: LibraryReading {
    private var reads: [CheckedContinuation<[LibraryPage], any Error>?] = []
    private(set) var requests: [[LibraryRequest]] = []
    private var waiting: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func libraries(_ requests: [LibraryRequest]) async throws -> [LibraryPage] {
        try await withCheckedThrowingContinuation { continuation in
            self.requests.append(requests)
            reads.append(continuation)
            if let waiting, reads.count >= waiting.count {
                self.waiting = nil
                waiting.continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard reads.count < count else { return }
        await withCheckedContinuation { waiting = (count, $0) }
    }

    func finish(_ index: Int, with result: Result<LibraryPage, any Error>) {
        finishBatch(index, with: result.map { Array(repeating: $0, count: requests[index].count) })
    }

    func finishBatch(_ index: Int, with result: Result<[LibraryPage], any Error>) {
        let continuation = reads[index]
        reads[index] = nil
        continuation?.resume(with: result)
    }
}

/// Hold an admitted autosave until the editor has committed its terminal operation.
@MainActor
private final class PausedDraftEditing: DraftEditing {
    let store: SnippetStore
    private var update: CheckedContinuation<Void, Never>?
    private var admitted: CheckedContinuation<Void, Never>?
    init(store: SnippetStore) { self.store = store }
    func updateDraft(_ draft: Draft) async throws {
        await withCheckedContinuation { continuation in
            update = continuation
            admitted?.resume()
            admitted = nil
        }
        try await store.updateDraft(draft)
    }
    func waitForUpdate() async {
        guard update == nil else { return }
        await withCheckedContinuation { admitted = $0 }
    }
    func resumeUpdate() { update?.resume(); update = nil }
    func keepDraft(_ draft: Draft) async throws { try await store.keepDraft(draft) }
    func discardDraft(_ draft: Draft) async throws { try await store.discardDraft(draft) }
    func save(_ draft: Draft, asNew: Bool) async throws -> UUID { try await store.save(draft, asNew: asNew) }
}
