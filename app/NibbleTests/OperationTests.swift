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
            #expect(library.error == nil)
        }

        @Test func tabLibrariesKeepIndependentQueriesAndRefreshSharedChanges() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let first = try await create(store, body: "定型文")
            let second = try await create(store, body: "検索だけに一致")
            try await store.setPinned(true, id: first)
            let all = LibraryModel(store: store)
            let pinned = LibraryModel(store: store, filter: .pinned)
            let search = LibraryModel(store: store)
            search.query = "検索だけ"
            search.showMore()
            await all.refresh()
            await pinned.refresh()
            await search.refresh()
            #expect(Set(all.items.map(\.id)) == [first, second])
            #expect(pinned.items.map(\.id) == [first])
            #expect(search.items.map(\.id) == [second])
            #expect(all.query.isEmpty && pinned.query.isEmpty)
            #expect(all.request.limit == LibraryRequest.pageSize)
            let item = try #require(all.items.first { $0.id == first })
            await all.pin(item)
            await pinned.refresh()
            #expect(pinned.items.isEmpty)
            await all.delete(second)
            await search.refresh()
            #expect(search.items.isEmpty)
            #expect(search.query == "検索だけ")
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
