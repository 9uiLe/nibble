import Foundation
import Testing
import Tasking
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Owned application work", .serialized)
    @MainActor
    struct OwnedActionTests {
        @Test func anInvalidatedPresentationDoesNotBlockOrOverwriteItsReplacement() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let opener = OpeningProbe()
            let model = LibraryModel(store: files.store, effects: RecordingLibraryEffects(), libraryOpener: opener)
            let oldOwner = LibraryTaskOwner()
            oldOwner.startTask(.open(.new), on: model)
            await opener.gate.waitForAdmissions(1)
            oldOwner.endScreen()
            let replacementOwner = LibraryTaskOwner()
            replacementOwner.startTask(.open(.new), on: model)
            await opener.gate.waitForAdmissions(2)
            let current = try await files.store.beginDraft()
            opener.gate.resolve(1, .success(current))
            await replacementOwner.waitForIdle()
            oldOwner.endScreen()
            let unused = try await files.store.beginDraft()
            opener.gate.resolve(0, .success(unused))
            await oldOwner.waitForIdle()
            #expect(model.editor?.id == current.id && model.failure == nil)
            #expect(try await files.store.drafts().map(\.id) == [current.id])
        }

        @Test func abandonedResumePreservesExistingInputAndCannotPublishFailure() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let input = try await files.store.beginDraft(body: "再開する入力")
            let opener = OpeningProbe()
            let model = LibraryModel(store: files.store, effects: RecordingLibraryEffects(), libraryOpener: opener)
            let owner = LibraryTaskOwner()
            owner.startTask(.open(.draft(input.id)), on: model)
            await opener.gate.waitForAdmissions(1)
            owner.endScreen()
            opener.gate.resolve(0, .success(input))
            await owner.waitForIdle()
            #expect(model.editor == nil && model.failure == nil)
            #expect(try await files.store.draft(input.id).body == input.body)
            owner.startTask(.open(.new), on: model)
            await opener.gate.waitForAdmissions(2)
            owner.endScreen()
            opener.gate.resolve(1, .failure(StoreError.database))
            await owner.waitForIdle()
            #expect(model.editor == nil && model.failure == nil)
        }

        @Test func sceneReloadSurvivesScreenExitAndDuplicatePoliciesRemainPerItem() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            _ = try await create(files.store, body: "一件目")
            _ = try await create(files.store, body: "二件目")
            let model = LibraryModel(store: files.store)
            let owner = LibraryTaskOwner()
            owner.startTask(.refresh, on: model)
            owner.endScreen()
            await owner.waitForIdle()
            #expect(model.items.count == 2 && !model.loading)
            let items = model.items
            let first = owner.startTask(.pin(items[0]), on: model)
            let duplicate = owner.startTask(.pin(items[0]), on: model)
            let independent = owner.startTask(.pin(items[1]), on: model)
            #expect(first.run != nil && independent.run != nil && duplicate.skipReason == .alreadyRunning)
            await owner.waitForIdle()
            #expect(try await files.store.search(filter: .pinned).count == 2)
        }

        @Test func finishingFreezesInputAndCommittedSaveSucceedsAfterCancellation() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let input = try await files.store.beginDraft(body: "保存する本文")
            let store = FinishProbe(store: files.store)
            let model = EditorModel(draft: input, store: store)
            let tasks = ViewTaskStore()
            var success = false
            tasks.start(id: "finish", lifetime: .screenBound, policy: .ignoreNew) { _ in success = await model.finish(.save) }
            await store.gate.waitForAdmissions(1)
            model.body = "入力を拒否する"
            #expect(model.body == input.body && model.phase == .finishing(.save))
            #expect(!(await model.finish(.keep)))
            tasks.cancel(lifetime: .screenBound)
            store.gate.resolve(0, .success(true))
            await tasks.waitForIdle()
            #expect(success && model.phase == .finished && model.failure == nil)
            #expect(try await files.store.search().first?.preview == input.body)
        }

        @Test func entitlementPublicationAcceptsOnlyTheLatestNoncancelledRequest() async {
            let reads = ApplicationGate<Date?>()
            var published: [Date?] = []
            let subscription = ProSubscription(readExpiration: { try? await reads.read() }, updateAccess: {
                published.append($0)
                return $0.map { $0 > Date() } ?? false
            })
            let tasks = ViewTaskStore()
            tasks.start(id: "old", lifetime: .sceneBound, policy: .ignoreNew) { _ in await subscription.refresh() }
            await reads.waitForAdmissions(1)
            tasks.start(id: "new", lifetime: .sceneBound, policy: .ignoreNew) { _ in await subscription.refresh() }
            await reads.waitForAdmissions(2)
            let expiry = Date().addingTimeInterval(3_600)
            reads.resolve(1, .success(expiry))
            await reads.waitForReturns(1)
            reads.resolve(0, .success(nil))
            await tasks.waitForIdle()
            #expect(published.count == 1 && published[0] == expiry && subscription.isActive && subscription.checked)
            tasks.start(id: "cancelled", lifetime: .sceneBound, policy: .ignoreNew) { _ in await subscription.refresh() }
            await reads.waitForAdmissions(3)
            tasks.cancel(lifetime: .sceneBound)
            reads.resolve(2, .success(nil))
            await tasks.waitForIdle()
            #expect(published.count == 1 && subscription.isActive)
        }
    }
}

@MainActor
private final class OpeningProbe: LibraryOpening {
    let gate = ApplicationGate<Draft>()
    func draft(_ id: UUID) async throws -> Draft { try await gate.read() }
    func editingDraft(for id: UUID) async throws -> Draft { try await gate.read() }
    func beginDraft(target: DraftTarget, body: String) async throws -> Draft { try await gate.read() }
}

@MainActor
private final class FinishProbe: DraftEditing {
    let store: SnippetStore
    let gate = ApplicationGate<Bool>()
    init(store: SnippetStore) { self.store = store }
    func updateDraft(_ draft: Draft) async throws { try await store.updateDraft(draft) }
    func keepDraft(_ draft: Draft) async throws { try await store.keepDraft(draft) }
    func discardDraft(_ draft: Draft) async throws { try await store.discardDraft(draft) }
    func save(_ draft: Draft, mode: DraftSaveMode) async throws -> UUID {
        _ = try await gate.read()
        return try await store.save(draft, mode: mode)
    }
}
