import Foundation
import Observation

@MainActor @Observable
final class EditorModel {
    enum Phase: Equatable { case editing, finishing, finished }
    enum FinishOperation { case save, saveAsNew, keep, discard }

    struct Failure: Equatable {
        let message: String
        let canSaveAsNew: Bool
    }

    private(set) var draft: Draft
    private(set) var phase = Phase.editing
    private(set) var failure: Failure?
    private let store: SnippetStore

    init(draft: Draft, store: SnippetStore) {
        self.draft = draft
        self.store = store
    }

    var title: String {
        get { draft.title }
        set { if phase == .editing { draft.title = newValue } }
    }

    var body: String {
        get { draft.body }
        set { if phase == .editing { draft.body = newValue } }
    }

    var canSave: Bool {
        phase == .editing && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func persist(_ snapshot: Draft) async {
        guard phase == .editing, snapshot.id == draft.id else { return }
        // An admitted write completes after cancellation. SQL ignores older and removed snapshots.
        do { try await store.updateDraft(snapshot) }
        catch {
            // A previous input's failure must not overwrite a newer input or a finish result.
            if phase == .editing && snapshot.sequence == draft.sequence {
                failure = Failure(message: "下書きを保存できませんでした。\n" + error.localizedDescription,
                                  canSaveAsNew: false)
            }
        }
    }

    /// Every exit freezes input, awaits persistence, then publishes exactly one terminal state.
    func finish(_ operation: FinishOperation) async -> Bool {
        guard !Task.isCancelled, phase == .editing else { return false }
        let snapshot = draft
        phase = .finishing
        failure = nil
        do {
            switch operation {
            case .save: try await store.save(snapshot)
            case .saveAsNew: try await store.save(snapshot, asNew: true)
            case .keep: try await store.keepDraft(snapshot)
            case .discard: try await store.discardDraft(snapshot)
            }
            phase = .finished
            return true
        } catch {
            phase = .editing
            let storeError = error as? StoreError
            failure = Failure(message: error.localizedDescription,
                              canSaveAsNew: storeError == .conflict || storeError == .staleDraft || storeError == .missing)
            return false
        }
    }
}

