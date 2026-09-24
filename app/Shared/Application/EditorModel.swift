import Foundation
import Observation

@MainActor @Observable
final class EditorModel {
    enum Phase: Equatable { case editing, finishing(FinishOperation), finished }
    enum FinishOperation: Equatable {
        case save, saveAsNew, keep, discard
    }

    struct Failure: Equatable {
        let reason: StoreError
        let operation: FinishOperation?
        enum Recovery { case retry, saveAsNew, correctInput, updateApplication }
        var recovery: Recovery {
            switch reason {
            case .conflict, .staleDraft, .missing: operation == nil ? .retry : .saveAsNew
            case .empty, .tooLarge: .correctInput
            case .newerVersion: .updateApplication
            default: .retry
            }
        }
        var canSaveAsNew: Bool { operation == .saveAsNew || recovery == .saveAsNew }
    }

    private(set) var draft: Draft
    private(set) var bodyRevision = 0
    private(set) var phase = Phase.editing
    private(set) var failure: Failure?
    private let store: any DraftEditing

    init(draft: Draft, store: any DraftEditing) {
        self.draft = draft
        self.store = store
    }

    var title: String {
        get { draft.title }
        set { if phase == .editing { draft.title = newValue } }
    }

    var body: String {
        get { draft.body }
        set {
            guard phase == .editing, !SnippetText.hasSameBytes(draft.body, newValue) else { return }
            draft.body = newValue
            bodyRevision += 1
        }
    }

    var hasBody: Bool { SnippetText.hasBody(draft.body) }
    var canSave: Bool { phase == .editing && hasBody }

    /// Pasting uses the same editing gate and input sequence as typed text.
    func appendToBody(_ text: String) { body += text }

    /// A nil selection means the body has no insertion position. A stale position never changes the body.
    func insertVariable(named name: String, at selection: NSRange?) -> NSRange? {
        guard phase == .editing, let marker = SnippetVariables.marker(for: name) else { return nil }
        let target = selection ?? NSRange(location: body.utf16.count, length: 0)
        guard let range = Range(target, in: body) else { return nil }
        var updated = body
        updated.replaceSubrange(range, with: marker)
        body = updated
        return NSRange(location: target.location + marker.utf16.count, length: 0)
    }

    func persist(_ snapshot: Draft) async {
        guard phase == .editing, snapshot.id == draft.id else { return }
        // An admitted write completes after cancellation. SQL ignores older and removed snapshots.
        do { try await store.updateDraft(snapshot) }
        catch {
            // A previous input's failure must not overwrite a newer input or a finish result.
            if phase == .editing && snapshot.sequence == draft.sequence {
                failure = Failure(reason: error as? StoreError ?? .database, operation: nil)
            }
        }
    }

    /// Every exit freezes input, awaits persistence, then publishes exactly one terminal state.
    func finish(_ operation: FinishOperation) async -> Bool {
        guard !Task.isCancelled, phase == .editing else { return false }
        let snapshot = draft
        phase = .finishing(operation)
        failure = nil
        do {
            switch operation {
            case .save: try await store.save(snapshot, asNew: false)
            case .saveAsNew: try await store.save(snapshot, asNew: true)
            case .keep: try await store.keepDraft(snapshot)
            case .discard: try await store.discardDraft(snapshot)
            }
            phase = .finished
            return true
        } catch {
            phase = .editing
            failure = Failure(reason: error as? StoreError ?? .database, operation: operation)
            return false
        }
    }

}
