import Foundation
import Testing
import Tasking
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Owned UI actions", .serialized)
    @MainActor
    struct OwnedActionTests {
        @Test func backgroundDoesNotCancelTheSceneReload() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
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
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let library = LibraryModel(store: store)
            let owner = LibraryTaskOwner()
            let first = owner.startTask(.open(.new), on: library)
            let duplicate = owner.startTask(.open(.new), on: library)
            #expect(first.run != nil)
            #expect(duplicate.skipReason == .alreadyRunning)
            await owner.waitForIdle()
            #expect(library.editor != nil)
            #expect(try await store.drafts().count == 1)
        }

        @Test func cancelledScreenOpenDoesNotBlockTheNextOpen() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let library = LibraryModel(store: store)
            let owner = LibraryTaskOwner()
            owner.startTask(.open(.new), on: library)
            owner.endScreen()
            await owner.waitForIdle()
            #expect(library.editor == nil)
            #expect(try await store.drafts().isEmpty)
            owner.startTask(.open(.new), on: library)
            await owner.waitForIdle()
            #expect(library.editor != nil)
            #expect(try await store.drafts().count == 1)
        }

        @Test func duplicatePolicyDoesNotDropActionsForDifferentItems() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
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
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let draft = try await store.beginDraft()
            let editor = EditorModel(draft: draft, store: store)
            for number in 0..<30 { editor.body = "日本語 \(number)" }
            #expect(await editor.finish(.save))
            let item = try #require(try await store.search().first)
            #expect(try await store.snippet(item.id).body == "日本語 29")
            #expect(try await store.drafts().isEmpty)
        }

        @Test func rapidInputCanResumeAfterClose() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let url = database.url
            let store = SnippetStore(location: url)
            let draft = try await store.beginDraft()
            let editor = EditorModel(draft: draft, store: store)
            for number in 0..<30 { editor.body = "下書き \(number)" }
            #expect(await editor.finish(.keep))
            let reopened = SnippetStore(location: url)
            #expect(try await reopened.draft(draft.id).body == "下書き 29")
            #expect(try await reopened.search().isEmpty)
        }
    }
}
