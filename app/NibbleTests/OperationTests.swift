import Foundation
import UIKit
import Testing
import Tasking
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Awaitable operations", .serialized)
    @MainActor
    struct AwaitableOperationTests {
        @Test func directAwaitCompletesEachLibraryOperation() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let library = LibraryModel(store: store)
            await library.open()
            let draft = try #require(library.editor)
            let editor = EditorModel(draft: draft, store: store)
            editor.title = "直接待機"
            editor.body = "  日本語\n👩🏽‍💻  "
            #expect(await editor.finish(.save))
            await library.refresh()
            let item = try #require(library.items.first)
            await library.copy(item.id)
            #expect(UIPasteboard.general.string == editor.body)
            #expect(library.notice?.message == "コピーしました") // Copy does not wait for notice expiry.
            await library.pin(item)
            #expect(library.items.first?.pinned == true)
            await library.delete(item.id)
            #expect(library.items.isEmpty)
            #expect(library.notice?.undoID == item.id)
            await library.restore(item.id)
            #expect(library.items.first?.id == item.id)
            await library.delete(item.id)
            await library.permanentlyDelete(item.id)
            #expect(try await store.search(filter: .trash).isEmpty)
            #expect(library.failure == nil)
        }

        @Test func librarySectionsKeepSearchIndependentAndRefreshSharedChanges() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let first = try await create(store, body: "定型文")
            let second = try await create(store, body: "検索だけに一致")
            try await store.setPinned(true, id: first)
            let all = LibraryModel(store: store)
            let search = LibraryModel(store: store)
            search.query = "検索だけ"
            search.showMore()
            await all.refresh()
            await search.refresh()
            #expect(Set(all.items.map(\.id)) == [first, second])
            #expect(all.page.pinnedItems.map(\.id) == [first])
            #expect(all.page.otherItems.map(\.id) == [second])
            #expect(search.items.map(\.id) == [second])
            #expect(all.query.isEmpty)
            #expect(all.request.limit == LibraryRequest.pageSize)
            let item = try #require(all.items.first { $0.id == first })
            await all.pin(item)
            #expect(all.page.pinnedItems.isEmpty)
            #expect(Set(all.page.otherItems.map(\.id)) == [first, second])
            await all.delete(second)
            await search.refresh()
            #expect(search.items.isEmpty)
            #expect(search.query == "検索だけ")
        }

        @Test func librarySectionsPreservePagingAndRestoration() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let pinned = try await create(store, body: "先頭に残す")
            try await store.setPinned(true, id: pinned)
            let other = try await create(store, body: "その他の項目")
            let firstPage = try await store.library(LibraryRequest(limit: 1))
            #expect(firstPage.pinnedItems.map(\.id) == [pinned])
            #expect(firstPage.otherItems.isEmpty && firstPage.hasMore)
            let expanded = try await store.library(LibraryRequest(limit: 1).expanded)
            #expect(expanded.pinnedItems.map(\.id) == [pinned])
            #expect(expanded.otherItems.map(\.id) == [other])
            #expect(!expanded.hasMore)
            let model = LibraryModel(store: store)
            await model.delete(pinned)
            #expect(model.page.pinnedItems.isEmpty)
            #expect(model.page.otherItems.map(\.id) == [other])
            await model.restore(pinned)
            #expect(model.page.pinnedItems.map(\.id) == [pinned])
            #expect(Set(model.items.map(\.id)) == [pinned, other])
            #expect(model.items.count == model.page.pinnedItems.count + model.page.otherItems.count)
        }

        @Test func libraryFiltersSeparateSavedPinnedAndDraftContent() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let pinned = try await create(store, body: "よく使う本文")
            let other = try await create(store, body: "保存済み")
            let deleted = try await create(store, body: "削除した本文")
            try await store.setPinned(true, id: pinned)
            try await store.setDeleted(true, id: deleted)
            let draft = try await store.beginDraft(body: "  未保存\n👩🏽‍💻  ")
            let all = try await store.library(LibraryRequest())
            #expect(Set(all.items.map(\.id)) == [pinned, other])
            #expect(all.drafts.map(\.id) == [draft.id])
            let pins = try await store.library(LibraryRequest(filter: .pinned))
            #expect(pins.items.map(\.id) == [pinned])
            #expect(pins.drafts.isEmpty)
            let drafts = try await store.library(LibraryRequest(filter: .drafts, limit: 1))
            #expect(drafts.items.isEmpty && !drafts.hasMore)
            #expect(drafts.drafts.map(\.id) == [draft.id])
            let trash = try await store.library(LibraryRequest(filter: .trash))
            #expect(trash.items.map(\.id) == [deleted] && trash.drafts.isEmpty)
            #expect(try await store.search(filter: .drafts).isEmpty)
            let model = LibraryModel(store: store, filter: .drafts)
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

        @Test func latestFilterResetsPagingAndKeepsSearchIndependent() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let saved = try await create(store, body: "検索対象")
            let draft = try await store.beginDraft(body: "下書き")
            let library = LibraryModel(store: store)
            let search = LibraryModel(store: store)
            search.query = "検索対象"
            await search.refresh()
            library.showMore()
            #expect(library.request.limit > LibraryRequest.pageSize)
            let owner = LibraryTaskOwner()
            library.filter = .pinned
            owner.startTask(.refresh, on: library)
            library.filter = .drafts
            owner.startTask(.refresh, on: library)
            await owner.waitForIdle()
            #expect(library.request.limit == LibraryRequest.pageSize)
            #expect(library.items.isEmpty && library.drafts.map(\.id) == [draft.id])
            #expect(!library.loading && library.failure == nil)
            #expect(search.items.map(\.id) == [saved] && search.query == "検索対象")
            #expect(search.filter == .all)
        }

        @Test func changingFilterCannotPresentUnloadedDataAsEmpty() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let saved = try await create(store, body: "ピン留めの本文")
            try await store.setPinned(true, id: saved)
            _ = try await store.beginDraft(body: "下書きの本文")
            let model = LibraryModel(store: store, filter: .pinned)
            await model.refresh()
            #expect(!model.loading && model.drafts.isEmpty)

            // SwiftUI renders the selection before onChange starts the async refresh.
            // An empty draft array here belongs to the pinned read, not to drafts.
            model.filter = .drafts
            #expect(model.loading, "The newly selected filter has not been read yet")
            #expect(model.contentRequest.filter == .pinned && !model.contentIsCurrent)
            #expect(model.items.map(\.id) == [saved])
            await model.refresh()
            #expect(!model.loading && model.drafts.count == 1)
            #expect(model.contentRequest.filter == .drafts && model.contentIsCurrent)

            model.filter = .all
            #expect(model.loading, "A draft-only result cannot establish an empty saved list")
            await model.refresh()
            #expect(!model.loading && model.items.map(\.id) == [saved])

            model.query = "か\u{3099}"
            await model.refresh()
            model.query = "が"
            #expect(model.contentIsCurrent && !model.loading,
                    "Canonical-equivalent queries describe the same search request")

            model.query = "一致しない語句"
            #expect(model.loading)
            await model.refresh()
            #expect(!model.loading && model.items.isEmpty)
        }

        @Test(arguments: [false, true])
        func staleReadCannotFinishTheNextSelection(fails: Bool) async throws {
            let reader = ControlledLibraryReader()
            let model = LibraryModel(filter: .pinned, libraryReader: reader)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            reader.finish(0, with: .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(!model.loading)

            model.filter = .drafts
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            // The next onChange has not started its task when the old read finishes.
            model.filter = .all
            reader.finish(1, with: fails ? .failure(StoreError.unavailable) : .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(model.loading && model.failure == nil)
            #expect(model.contentRequest.filter == .pinned && !model.contentIsCurrent)

            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(3)
            reader.finish(2, with: .success(LibraryPage()))
            await owner.waitForIdle()
            #expect(!model.loading && model.contentIsCurrent && model.failure == nil)
            #expect(model.contentRequest.filter == .all)
        }

        @Test func lateReadCannotReplaceTheLatestResult() async throws {
            let reader = ControlledLibraryReader()
            let model = LibraryModel(filter: .pinned, libraryReader: reader)
            let olderOwner = LibraryTaskOwner()
            let latestOwner = LibraryTaskOwner()
            olderOwner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            model.filter = .drafts
            latestOwner.startTask(.refresh, on: model)
            await reader.waitForRequests(2)
            reader.finish(1, with: .success(LibraryPage()))
            await latestOwner.waitForIdle()
            #expect(!model.loading && model.contentRequest.filter == .drafts)
            reader.finish(0, with: .failure(StoreError.unavailable))
            await olderOwner.waitForIdle()
            #expect(!model.loading && model.failure == nil && model.contentIsCurrent)
            #expect(model.contentRequest.filter == .drafts)
        }

        @Test func failedFilterReadDoesNotBecomeAnEmptyResultOrLeakIntoAnotherFilter() async throws {
            let reader = ControlledLibraryReader()
            let model = LibraryModel(libraryReader: reader)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            await reader.waitForRequests(1)
            reader.finish(0, with: .failure(StoreError.unavailable))
            await owner.waitForIdle()
            #expect(!model.loading && !model.contentIsCurrent && model.failure != nil)
            model.filter = .drafts
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
        func creatingFromFilteredLibraryReturnsToAll(filter: LibraryFilter) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = LibraryModel(store: database.store, filter: filter)
            await model.open(.new)
            let draft = try #require(model.editor)
            #expect(model.filter == .all)
            await model.refresh()
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

        @Test func admittedAutosaveAndImmediateSaveCannotResurrectDraft() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let editor = EditorModel(draft: try await store.beginDraft(), store: store)
            editor.body = "途中"
            let snapshot = editor.draft
            async let autosave: Void = editor.persist(snapshot)
            editor.body = "保存する最新値"
            #expect(await editor.finish(.save))
            await autosave
            await editor.persist(snapshot)
            #expect(try await store.drafts().isEmpty)
            let item = try #require(try await store.search().first)
            #expect(try await store.snippet(item.id).body == "保存する最新値")
        }

        @Test func discardCompletesAndRejectsLateAutosave() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let editor = EditorModel(draft: try await store.beginDraft(), store: store)
            editor.body = "破棄する入力"
            let snapshot = editor.draft
            async let autosave: Void = editor.persist(snapshot)
            #expect(await editor.finish(.discard))
            await autosave
            await editor.persist(snapshot)
            #expect(try await store.drafts().isEmpty)
            #expect(try await store.search().isEmpty)
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
            #expect(try await store.drafts().isEmpty)
            #expect(try await store.snippet(id).deleted == false)
        }

        @Test func supersededRefreshPublishesTheLatestQuery() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
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

        @Test func emptySearchPreservesOperationFailureUntilExplicitRecovery() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let library = LibraryModel(store: database.store)
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
            let library = LibraryModel(store: SnippetStore(location: file.appending(path: "db.sqlite")))
            await library.refresh()
            #expect(library.failure?.title == "一覧を読み込めませんでした")
            #expect(library.failure?.recovery == .reload)
            await library.open()
            #expect(library.failure?.title == "編集を始められませんでした")
            #expect(library.editor == nil)
            library.dismissFailure()
            #expect(library.failure?.title == "一覧を読み込めませんでした")
            try FileManager.default.removeItem(at: file)
            await library.reload()
            #expect(library.failure == nil && !library.loading)
        }

        @Test func consecutiveDeletionsKeepTheUndoSubjectAndIdentityTogether() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let first = try await create(store, title: "一つ目", body: "原文1")
            let second = try await create(store, title: "二つ目", body: "原文2")
            let library = LibraryModel(store: store)
            await library.refresh()
            await library.delete(first)
            #expect(library.notice?.subject == "一つ目" && library.notice?.undoID == first)
            await library.delete(second)
            #expect(library.notice?.subject == "二つ目" && library.notice?.undoID == second)
            #expect(library.notice?.announcement.contains("二つ目") == true)
            await library.restore(try #require(library.notice?.undoID))
            #expect(library.notice?.subject == "二つ目")
            #expect(try await store.snippet(first).deleted)
            #expect(try await store.snippet(second).body == "原文2")
            #expect(try await store.snippet(second).deleted == false)
            await library.permanentlyDelete(first)
            #expect(library.notice?.subject == "一つ目")
        }

        @Test func editorExplainsRequiredBodyWithoutChangingOriginalInput() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let draft = try await database.store.beginDraft()
            let editor = EditorModel(draft: draft, store: database.store)
            editor.title = "名前だけ"
            for body in ["", "  ", "\n\t"] {
                editor.body = body
                #expect(!editor.hasBody && !editor.canSave)
                #expect(editor.body.utf8.elementsEqual(body.utf8))
            }
            let original = "  原文\n👩🏽‍💻  "
            editor.body = original
            #expect(editor.hasBody && editor.canSave)
            #expect(await editor.finish(.keep))
            #expect(try await database.store.draft(draft.id).body.utf8.elementsEqual(original.utf8))
        }

        @Test func noticeExpiryIsSeparateAndCancellationPreservesNotice() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let id = try await create(store, body: "copy")
            let library = LibraryModel(store: store)
            await library.copy(id)
            let first = try #require(library.notice?.id)
            let tasks = ViewTaskStore()
            tasks.start(id: "notice.expiry", lifetime: .screenBound) { _ in
                await library.expireNotice(id: first)
            }
            tasks.cancelAll()
            await tasks.waitForIdle()
            #expect(library.notice?.id == first)
            await library.copy(id)
            #expect(library.notice?.id != first)
            // A stale ID is ignored without clearing the replacement notice.
            await library.expireNotice(id: first)
            #expect(library.notice != nil)
            await library.expireNotice(id: try #require(library.notice?.id))
            #expect(library.notice == nil)
            #expect(library.notice?.undoID == nil)
        }
    }
}

/// Explicit completion gates reproduce request ordering without sleeps or scheduler assumptions.
@MainActor
private final class ControlledLibraryReader: LibraryReading {
    private var reads: [CheckedContinuation<LibraryPage, any Error>?] = []
    private var waiting: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func library(_ request: LibraryRequest) async throws -> LibraryPage {
        try await withCheckedThrowingContinuation { continuation in
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
        let continuation = reads[index]
        reads[index] = nil
        continuation?.resume(with: result)
    }
}
