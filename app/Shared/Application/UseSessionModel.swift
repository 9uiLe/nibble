import Foundation
import Observation

@MainActor @Observable
final class UseSessionModel: Identifiable {
    let id = UUID()
    private let storage: any WorkspaceStorage
    @ObservationIgnored private var checkpointInProgress = false
    @ObservationIgnored private var checkpointWaiters: [CheckedContinuation<Void, Never>] = []
    private var independentDraft: WorkDraft?
    private(set) var card: TextCard
    private(set) var draft: WorkDraft?
    private(set) var error: WorkspaceError?
    private(set) var discardsLocalInputOnly = false
    private(set) var busy = false
    private(set) var copied = false
    private(set) var completionSaved = false
    var isComposing = false

    init(card: TextCard, draft: WorkDraft?, storage: any WorkspaceStorage) {
        self.card = card
        self.draft = draft
        self.storage = storage
    }

    var savedSequence: Int? { draft?.checkpointSequence }
    var hasIndependentRecovery: Bool { independentDraft != nil }
    var names: [String] {
        guard draft?.usesVariables ?? card.usesVariables else { return [] }
        return TextTemplate(draft?.body ?? card.body).names
    }
    var values: [String: String] { draft?.values ?? [:] }
    var title: String { draft?.title ?? card.title }
    var output: String? {
        if let draft { return try? draft.renderedBody() }
        if card.usesVariables { return try? TextTemplate(card.body).render(values: values) }
        return card.body
    }

    func updateValue(_ value: String, for name: String) {
        guard var changed = draft, !copied, !busy else { return }
        var values = changed.values
        values[name] = value
        do {
            try changed.update(title: changed.title, body: changed.body, values: values)
            draft = changed
            error = nil
        } catch { recordFailure(error) }
    }

    func updateTitle(_ title: String) {
        guard var changed = draft, !copied, !busy else { return }
        do {
            try changed.update(title: title, body: changed.body, values: changed.values)
            draft = changed
        } catch { recordFailure(error) }
    }

    @discardableResult
    func checkpoint() async -> Bool {
        while checkpointInProgress {
            await withCheckedContinuation { checkpointWaiters.append($0) }
        }
        guard !copied else { return true }
        checkpointInProgress = true
        defer {
            checkpointInProgress = false
            let waiting = checkpointWaiters
            checkpointWaiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
        while let snapshot = draft {
            do {
                let retained = try await storage.checkpoint(snapshot)
                draft?.acknowledgeCheckpoint(retained)
                if draft?.sequence == snapshot.sequence { error = nil; return true }
                if Task.isCancelled { return false }
            } catch {
                guard draft?.sequence == snapshot.sequence else { return false }
                recordFailure(error)
                return false
            }
        }
        return true
    }

    func suspend() async -> Bool {
        guard !busy, !isComposing else { return false }
        busy = true
        defer { busy = false }
        return await checkpoint()
    }

    func copy(using delivery: any TextDelivery) async {
        guard !busy, !copied, !isComposing else { return }
        busy = true
        defer { busy = false }
        let expectedSequence = draft?.sequence
        guard await checkpoint() else { return }
        do {
            _ = try await storage.revalidate(cardID: card.id, expectedVersion: card.version)
            guard !Task.isCancelled, !isComposing, expectedSequence == draft?.sequence else { return }
            let body: String
            if let draft { body = try draft.renderedBody() }
            else { body = card.usesVariables ? try TextTemplate(card.body).render(values: values) : card.body }
            delivery.copy(body)
            copied = true
            error = nil
            // Cleanup failure never repeats the completed external effect.
            if let draft {
                do { try await storage.discardDraft(id: draft.id, expectedSequence: draft.sequence) }
                catch { recordFailure(error) }
            }
        } catch { recordFailure(error) }
    }

    func saveCompletion() async -> Bool {
        guard !busy, !copied, !isComposing, let draft, output != nil else { return false }
        busy = true
        defer { busy = false }
        guard await checkpoint() else { return false }
        do {
            card = try await storage.publish(draft)
            self.draft = nil
            completionSaved = true
            error = nil
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    func discard() async -> Bool {
        guard !busy, !isComposing else { return false }
        busy = true
        defer { busy = false }
        guard let draft else { return true }
        if discardsLocalInputOnly { return true }
        guard await checkpoint() else { return discardsLocalInputOnly }
        do {
            try await storage.discardDraft(id: draft.id, expectedSequence: draft.sequence)
            return true
        } catch {
            recordFailure(error)
            return discardsLocalInputOnly
        }
    }

    func saveIndependentCompletion() async -> Bool {
        guard !busy, !copied, !completionSaved, !isComposing, let output else { return false }
        busy = true
        defer { busy = false }
        do {
            var independent: WorkDraft
            if let independentDraft {
                independent = try await storage.checkpoint(independentDraft)
            } else {
                independent = try await storage.beginDraft(title: title, body: output)
                independentDraft = independent
            }
            try independent.update(title: title, body: output, values: [:])
            independentDraft = independent
            card = try await storage.publish(independent)
            independentDraft = nil
            draft = nil
            completionSaved = true
            error = nil
            return true
        } catch {
            recordFailure(error)
            return false
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
