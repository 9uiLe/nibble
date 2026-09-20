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
            #expect(library.failure == nil)
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

        @Test(arguments: [false, true])
        func leavingDuringDraftLookupDoesNotPresentOrReport(providerFails: Bool) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let opener = ControlledLibraryOpener()
            let library = LibraryModel(store: database.store, effects: RecordingLibraryEffects(), libraryOpener: opener)
            let owner = LibraryTaskOwner()
            owner.startTask(.open(.new), on: library)
            await opener.waitForRequests(1)
            owner.endScreen()
            let draft = try await database.store.beginDraft()
            opener.finish(0, with: providerFails ? .failure(StoreError.missing) : .success(draft))
            await owner.waitForIdle()
            #expect(library.editor == nil)
            #expect(library.failure == nil)
            if !providerFails { #expect(try await database.store.drafts().isEmpty) }
        }

        @Test(arguments: [false, true])
        func cancelledOpenCanReenterBeforeTheOldLookupCompletes(oldFails: Bool) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let opener = ControlledLibraryOpener()
            let library = LibraryModel(store: database.store, effects: RecordingLibraryEffects(), libraryOpener: opener)
            let oldOwner = LibraryTaskOwner()
            oldOwner.startTask(.open(.new), on: library)
            await opener.waitForRequests(1)
            oldOwner.endScreen()
            let nextOwner = LibraryTaskOwner()
            nextOwner.startTask(.open(.new), on: library)
            await opener.waitForRequests(2)
            // Ending the old owner again cannot invalidate the new owner's request.
            oldOwner.endScreen()
            let current = try await database.store.beginDraft()
            opener.finish(1, with: .success(current))
            await nextOwner.waitForIdle()
            #expect(library.editor?.id == current.id)
            if oldFails {
                opener.finish(0, with: .failure(StoreError.missing))
            } else {
                let unused = try await database.store.beginDraft()
                opener.finish(0, with: .success(unused))
            }
            await oldOwner.waitForIdle()
            #expect(library.editor?.id == current.id)
            #expect(library.failure == nil)
            #expect(try await database.store.drafts().map(\.id) == [current.id])
        }

        @Test func cancelledResumeKeepsTheExistingDraft() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let draft = try await database.store.beginDraft(body: "保持する入力")
            let opener = ControlledLibraryOpener()
            let library = LibraryModel(store: database.store, effects: RecordingLibraryEffects(), libraryOpener: opener)
            let owner = LibraryTaskOwner()
            owner.startTask(.open(.draft(draft.id)), on: library)
            await opener.waitForRequests(1)
            owner.endScreen()
            opener.finish(0, with: .success(draft))
            await owner.waitForIdle()
            #expect(library.editor == nil && library.failure == nil)
            #expect(try await database.store.draft(draft.id).body == "保持する入力")
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
            #expect(library.failure == nil)
        }

    }
}

@MainActor
private final class ControlledLibraryOpener: LibraryOpening {
    private var requests: [CheckedContinuation<Draft, any Error>?] = []
    private var waiting: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func beginDraft(snippetID: UUID?, body: String) async throws -> Draft { try await read() }
    func editingDraft(for id: UUID) async throws -> Draft { try await read() }
    func draft(_ id: UUID) async throws -> Draft { try await read() }

    private func read() async throws -> Draft {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(continuation)
            if let waiting, requests.count >= waiting.count {
                self.waiting = nil
                waiting.continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiting = (count, $0) }
    }

    func finish(_ index: Int, with result: Result<Draft, any Error>) {
        let continuation = requests[index]
        requests[index] = nil
        continuation?.resume(with: result)
    }
}
