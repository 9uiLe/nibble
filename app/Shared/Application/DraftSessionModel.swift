import Foundation
import Observation

@MainActor @Observable
final class DraftSessionModel: Identifiable {
    let id: UUID
    private let storage: any WorkspaceStorage
    @ObservationIgnored private var checkpointInProgress = false
    @ObservationIgnored private var checkpointWaiters: [CheckedContinuation<Void, Never>] = []
    private var independentDraft: WorkDraft?
    private var independentResult: TextCard?
    private(set) var draft: WorkDraft
    private(set) var error: WorkspaceError?
    private(set) var discardsLocalInputOnly = false
    private(set) var busy = false
    var isComposing = false

    init(draft: WorkDraft, storage: any WorkspaceStorage) {
        id = draft.id
        self.draft = draft
        self.storage = storage
    }

    var savedSequence: Int { draft.checkpointSequence }
    var hasCheckpoint: Bool { !discardsLocalInputOnly && savedSequence == draft.sequence }
    var hasIndependentRecovery: Bool { independentDraft != nil }

    func update(title: String? = nil, body: String? = nil, usesVariables: Bool? = nil) {
        guard !busy else { return }
        do {
            try draft.update(title: title ?? draft.title, body: body ?? draft.body, values: draft.values, usesVariables: usesVariables)
        } catch {
            recordFailure(error)
        }
    }

    @discardableResult
    func checkpoint() async -> Bool {
        while checkpointInProgress {
            await withCheckedContinuation { checkpointWaiters.append($0) }
        }
        checkpointInProgress = true
        defer {
            checkpointInProgress = false
            let waiting = checkpointWaiters
            checkpointWaiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
        while true {
            let snapshot = draft
            do {
                let retained = try await storage.checkpoint(snapshot)
                draft.acknowledgeCheckpoint(retained)
                if draft.sequence == snapshot.sequence { error = nil; return true }
                if Task.isCancelled { return false }
            } catch {
                guard draft.sequence == snapshot.sequence else { return false }
                recordFailure(error)
                return false
            }
        }
    }

    func suspend() async -> Bool {
        guard !busy, !isComposing else { return false }
        busy = true
        defer { busy = false }
        return await checkpoint()
    }

    func save() async -> TextCard? {
        guard !busy, !isComposing else { return nil }
        busy = true
        defer { busy = false }
        guard await checkpoint() else { return nil }
        do {
            let result = try await storage.publish(draft)
            error = nil
            return result
        } catch {
            recordFailure(error)
            return nil
        }
    }

    func discard() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        if discardsLocalInputOnly { return true }
        guard await checkpoint() else { return discardsLocalInputOnly }
        do {
            try await storage.discardDraft(id: id, expectedSequence: draft.sequence)
            return true
        } catch {
            recordFailure(error)
            return discardsLocalInputOnly
        }
    }

    func saveAsNew() async -> TextCard? {
        guard !busy, !isComposing else { return nil }
        if let independentResult { return independentResult }
        busy = true
        defer { busy = false }
        do {
            var independent: WorkDraft
            if let independentDraft {
                independent = try await storage.checkpoint(independentDraft)
            } else {
                independent = try await storage.beginDraft(title: draft.title, body: draft.body)
                independentDraft = independent
            }
            try independent.update(title: draft.title, body: draft.body, values: [:], usesVariables: draft.usesVariables)
            independentDraft = independent
            let result = try await storage.publish(independent)
            independentResult = result
            independentDraft = nil
            error = nil
            return result
        } catch {
            recordFailure(error)
            return nil
        }
    }

    private func recordFailure(_ error: any Error) {
        let failure = WorkspaceError.normalize(error)
        self.error = failure
        switch failure {
        case .staleCheckpoint, .missingDraft: discardsLocalInputOnly = true
        default: break
        }
    }
}
