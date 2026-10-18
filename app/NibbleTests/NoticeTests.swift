import Foundation
import Testing
import Tasking
@testable import Nibble

@Suite("Committed results and their notices", .serialized)
@MainActor
struct NoticeContractTests {
    @Test func replacingANoticeCannotUndoAnEarlierSubject() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let first = try await create(fixture.store, title: "最初", body: "一つ目")
        let second = try await create(fixture.store, title: "次", body: "二つ目")
        let model = LibraryModel(store: fixture.store)
        model.query = "本文"
        await model.delete(first)
        let old = try #require(model.notice)
        await model.copy(second)
        let current = try #require(model.notice)
        #expect(current.id != old.id && current.undoID == nil && current.subject == nil)
        await model.undoNotice(old.id)
        #expect(try await fixture.store.snippet(first).deleted)
        #expect(model.notice?.id == current.id && model.query == "本文")
        await model.delete(second)
        let deletion = try #require(model.notice)
        #expect(deletion.undoID == second && deletion.subject == "次")
        await model.undoNotice(deletion.id)
        #expect(try await !fixture.store.snippet(second).deleted)
        #expect(model.notice?.undoID == nil && model.notice?.subject == "次")
    }

    @Test func expiryBelongsToTheDisplayedNoticeAndNeverDeletesPersistedText() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "期限が過ぎても本文は残る")
        let gate = NoticeDeadlineGate()
        let model = LibraryModel(store: fixture.store, effects: RecordingLibraryEffects(), noticeSleep: { try await gate.suspend($0) })
        await model.copy(id)
        let old = try #require(model.notice?.id)
        #expect(gate.deadlines.isEmpty)
        let tasks = ViewTaskStore()
        let oldRun = tasks.start(id: "notice.old", lifetime: .screenBound) { _ in await model.expireNotice(id: old) }
        await gate.waitForCount(1)
        await model.delete(id)
        let current = try #require(model.notice?.id)
        tasks.start(id: "notice.current", lifetime: .screenBound) { _ in await model.expireNotice(id: current) }
        await gate.waitForCount(2)
        gate.finish(0)
        await tasks.awaitCompletion(of: try #require(oldRun.run))
        #expect(model.notice?.id == current)
        gate.finish(1)
        await tasks.waitForIdle()
        #expect(model.notice == nil)
        #expect(try await fixture.store.snippet(id).deleted)
        await model.restore(id)
        #expect(try await fixture.store.savedBody(id) == "期限が過ぎても本文は残る")
    }

    @Test func leavingTheSurfaceInvalidatesItsFeedbackWithoutLosingEditorInput() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "編集する本文")
        let model = LibraryModel(store: fixture.store)
        await model.copy(id)
        #expect(model.notice != nil)
        model.setNoticePresentation(false)
        model.setNoticePresentation(true)
        #expect(model.notice == nil)
        await model.open(.snippet(id))
        #expect(model.editor?.body == "編集する本文")
        #expect(model.notice == nil)
    }
}

@MainActor
private final class NoticeDeadlineGate {
    private(set) var deadlines: [ContinuousClock.Instant] = []
    private var pending: [CheckedContinuation<Void, Never>?] = []
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    func suspend(_ deadline: ContinuousClock.Instant) async throws {
        deadlines.append(deadline)
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            if let waiter, pending.count >= waiter.0 {
                self.waiter = nil
                waiter.1.resume()
            }
        }
        try Task.checkCancellation()
    }

    func waitForCount(_ count: Int) async {
        guard pending.count < count else { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func finish(_ index: Int) {
        let continuation = pending[index]
        pending[index] = nil
        continuation?.resume()
    }
}
