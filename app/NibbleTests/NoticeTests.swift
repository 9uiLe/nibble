import Foundation
import Testing
import Tasking
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Operation result notifications", .serialized)
    @MainActor
    struct NoticeTests {
        @Test func latestResultKeepsMessageSubjectTargetAndOriginTogether() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let first = try await create(files.store, title: "一つ目", body: "本文1")
            let second = try await create(files.store, title: "二つ目", body: "本文2")
            let effects = RecordingLibraryEffects()
            let model = LibraryModel(store: files.store, effects: effects)
            model.query = "本文"
            await model.delete(first)
            let deleted = try #require(model.notice)
            #expect(deleted.origin == .library)
            #expect(deleted.subject == "一つ目" && deleted.undoID == first)
            await model.copy(second)
            let copied = try #require(model.notice)
            #expect(copied.message == "コピーしました")
            #expect(copied.id != deleted.id && copied.subject == nil && copied.undoID == nil)
            await model.undoNotice(deleted.id)
            #expect(try await files.store.snippet(first).deleted)
            #expect(model.notice?.id == copied.id)
            await model.copy(second)
            #expect(model.notice?.id != copied.id)
            #expect(model.query == "本文")
            await model.restore(first)
            await model.delete(first)
            let firstDeletion = try #require(model.notice)
            await model.delete(second)
            #expect(model.notice?.subject == "二つ目" && model.notice?.undoID == second)
            #expect(model.notice?.id != firstDeletion.id)
            #expect(model.notice?.announcement.contains("二つ目") == true)
            await model.undoNotice(try #require(model.notice?.id))
            #expect(model.notice?.message == "元に戻しました")
            #expect(model.notice?.subject == "二つ目" && model.notice?.undoID == nil)
            #expect(try await files.store.snippet(first).deleted)
            #expect(try await !files.store.snippet(second).deleted)
            await model.permanentlyDelete(first)
            #expect(model.notice?.subject == "一つ目" && model.failure == nil)
            #expect(try await files.store.search(filter: .trash).isEmpty)
            await #expect(throws: StoreError.missing) { try await files.store.snippet(first) }
        }

        @Test func queuedUIActionBelongsToTheVisitThatAcceptedIt() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "コピーは完了する")
            let effects = RecordingLibraryEffects()
            let model = LibraryModel(store: files.store, effects: effects)
            let owner = LibraryTaskOwner()
            owner.startTask(.copy(id), on: model)
            model.setNoticePresentation(false)
            model.setNoticePresentation(true)
            await owner.waitForIdle()
            #expect(model.notice == nil && model.feedback == 0)
            #expect(effects.events == [.copy("コピーは完了する")])
            #expect(try await files.store.snippet(id).usage.count == 1)
        }

        @Test(arguments: [false, true])
        func leavingAndReturningRejectsLateResults(copy: Bool) async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "遅れて完了する")
            let storage = PausedNoticeStorage(store: files.store)
            storage.pausesBody = copy
            storage.pausesMutation = !copy
            let effects = RecordingLibraryEffects()
            let model = LibraryModel(store: storage, effects: effects)
            let owner = LibraryTaskOwner()
            owner.startTask(copy ? .copy(id) : .delete(id), on: model)
            await storage.gate.waitForRequests(1)
            model.setNoticePresentation(false) // Tab departure, sheet presentation or background.
            owner.endScreen()
            model.setNoticePresentation(true)
            storage.gate.finish(0)
            await owner.waitForIdle()
            #expect(model.notice == nil && model.feedback == 0 && model.failure == nil)
            #expect(try await files.store.snippet(id).deleted == !copy)
            #expect(effects.events == (copy ? [.copy("遅れて完了する")] : []))
        }

        @Test func restorationFinishesAfterLeavingWithoutReplayingFeedback() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "復元する本文")
            let storage = PausedNoticeStorage(store: files.store)
            let effects = RecordingLibraryEffects()
            let model = LibraryModel(store: storage, effects: effects)
            await model.delete(id)
            let notice = try #require(model.notice)
            let feedback = model.feedback
            let events = effects.events
            storage.pausesMutation = true
            let owner = LibraryTaskOwner()
            owner.startTask(.undoNotice(notice.id), on: model)
            await storage.gate.waitForRequests(1)
            model.setNoticePresentation(false)
            owner.endScreen()
            model.setNoticePresentation(true)
            storage.gate.finish(0)
            await owner.waitForIdle()
            #expect(try await !files.store.snippet(id).deleted)
            #expect(model.notice == nil && model.failure == nil && model.restoringIDs.isEmpty)
            #expect(model.feedback == feedback && effects.events == events)
        }

        @Test func undoIsOwnedDeduplicatedAndRecoverableAfterFailure() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, title: "復元対象", body: "本文")
            let storage = PausedNoticeStorage(store: files.store)
            let model = LibraryModel(store: storage, effects: RecordingLibraryEffects())
            await model.delete(id)
            let notice = try #require(model.notice)
            storage.pausesMutation = true
            let owner = LibraryTaskOwner()
            let anotherOwner = LibraryTaskOwner()
            #expect(owner.startTask(.undoNotice(notice.id), on: model).run != nil)
            #expect(owner.startTask(.undoNotice(notice.id), on: model).skipReason == .alreadyRunning)
            await storage.gate.waitForRequests(1)
            anotherOwner.startTask(.undoNotice(notice.id), on: model)
            await anotherOwner.waitForIdle()
            #expect(model.restoringIDs == [id] && storage.restoreCalls == 1)
            storage.gate.finish(0, error: StoreError.unavailable)
            await owner.waitForIdle()
            #expect(model.restoringIDs.isEmpty && model.notice == nil)
            #expect(model.failure?.recovery == .retryRestore(id))
            #expect(try await files.store.snippet(id).deleted)
            storage.pausesMutation = false
            await model.restore(id)
            #expect(model.failure == nil && model.notice?.message == "元に戻しました")
            #expect(try await !files.store.snippet(id).deleted)
            #expect(storage.restoreCalls == 2)
        }

        @Test func displayOwnsDeadlineCancellationAndReplacement() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "期限")
            let sleeper = PausedNoticeSleeper()
            let model = LibraryModel(store: files.store, effects: RecordingLibraryEffects(), noticeSleep: { try await sleeper.sleep(until: $0) })
            await model.copy(id)
            let first = try #require(model.notice?.id)
            #expect(sleeper.deadlines.isEmpty, "A data operation does not start a display timer")
            let tasks = ViewTaskStore()
            let beforeCopyDisplay = ContinuousClock.now
            let firstRun = tasks.start(id: "first", lifetime: .screenBound) { _ in await model.expireNotice(id: first) }
            await sleeper.gate.waitForRequests(1)
            let afterCopyDisplay = ContinuousClock.now
            let firstDeadline = try #require(sleeper.deadlines.first)
            #expect(firstDeadline >= beforeCopyDisplay.advanced(by: .seconds(2)))
            #expect(firstDeadline <= afterCopyDisplay.advanced(by: .seconds(2)))
            do {
                let tasks = ViewTaskStore()
                tasks.start(id: "cancelled", lifetime: .screenBound) { _ in await model.expireNotice(id: first) }
                await sleeper.gate.waitForRequests(2)
                tasks.cancelAll()
                sleeper.gate.finish(1)
                await tasks.waitForIdle()
            }
            #expect(model.notice?.id == first)
            let remountedRun = tasks.start(id: "remount", lifetime: .screenBound) { _ in await model.expireNotice(id: first) }
            await sleeper.gate.waitForRequests(3)
            #expect(sleeper.deadlines[2] == firstDeadline)
            await model.delete(id)
            let latest = try #require(model.notice?.id)
            let beforeDeleteDisplay = ContinuousClock.now
            tasks.start(id: "latest", lifetime: .screenBound) { _ in await model.expireNotice(id: latest) }
            await sleeper.gate.waitForRequests(4)
            let afterDeleteDisplay = ContinuousClock.now
            #expect(sleeper.deadlines[3] >= beforeDeleteDisplay.advanced(by: .seconds(6)))
            #expect(sleeper.deadlines[3] <= afterDeleteDisplay.advanced(by: .seconds(6)))
            sleeper.gate.finish(0)
            sleeper.gate.finish(2)
            await tasks.awaitCompletion(of: try #require(firstRun.run))
            await tasks.awaitCompletion(of: try #require(remountedRun.run))
            #expect(model.notice?.id == latest && model.notice?.undoID == id)
            sleeper.gate.finish(3)
            await tasks.waitForIdle()
            #expect(model.notice == nil)
            #expect(try await files.store.snippet(id).deleted, "Expiry never permanently deletes data")
            await model.restore(id)
            #expect(try await !files.store.snippet(id).deleted)
        }

        @Test func sheetPresentationEndsTheNoticeWithoutChangingEditorInput() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "編集する本文")
            let model = LibraryModel(store: files.store)
            await model.copy(id)
            #expect(model.notice != nil)
            await model.open(.snippet(id))
            #expect(model.notice == nil && !model.noticeContext.isPresented)
            #expect(model.editor?.body == "編集する本文")
            model.setNoticePresentation(true)
            #expect(model.notice == nil)
        }
    }
}

@MainActor
private final class NoticeTestGate {
    private var requests: [CheckedContinuation<Void, any Error>?] = []
    private var waiting: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    func pause() async throws {
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
    func finish(_ index: Int, error: (any Error)? = nil) {
        let continuation = requests[index]
        requests[index] = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }
}

@MainActor
private final class PausedNoticeSleeper {
    let gate = NoticeTestGate()
    private(set) var deadlines: [ContinuousClock.Instant] = []
    func sleep(until deadline: ContinuousClock.Instant) async throws {
        deadlines.append(deadline)
        try await gate.pause()
    }
}

@MainActor
private final class PausedNoticeStorage: LibraryStorage {
    let store: SnippetStore
    let gate = NoticeTestGate()
    var pausesBody = false
    var pausesMutation = false
    private(set) var restoreCalls = 0
    init(store: SnippetStore) { self.store = store }
    func savedBody(_ id: UUID) async throws -> String {
        if pausesBody { try await gate.pause() }
        return try await store.savedBody(id)
    }
    func mutate(_ mutation: SnippetMutation, id: UUID) async throws -> SnippetSummary {
        if case .restore = mutation { restoreCalls += 1 }
        if pausesMutation { try await gate.pause() }
        return try await store.mutate(mutation, id: id)
    }
    func libraries(_ requests: [LibraryRequest]) async throws -> [LibraryPage] { try await store.libraries(requests) }
    func beginDraft(snippetID: UUID?, body: String) async throws -> Draft { try await store.beginDraft(snippetID: snippetID, body: body) }
    func editingDraft(for id: UUID) async throws -> Draft { try await store.editingDraft(for: id) }
    func draft(_ id: UUID) async throws -> Draft { try await store.draft(id) }
    func keepDraft(_ draft: Draft) async throws { try await store.keepDraft(draft) }
    func setPinned(_ pinned: Bool, id: UUID) async throws { try await store.setPinned(pinned, id: id) }
    func recordUse(_ use: SnippetUse) async throws { try await store.recordUse(use) }
}
