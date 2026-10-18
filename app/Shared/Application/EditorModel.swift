import Foundation
import Observation

@MainActor @Observable
final class EditorModel {
    enum FinishOperation: Equatable {
        case save, saveAsNew, keep, discard
    }

    enum Phase: Equatable {
        case editing
        case finishing(FinishOperation)
        case finished
    }

    struct Failure: Equatable {
        enum Recovery { case retry, saveAsNew, correctInput, updateApplication }
        let reason: StoreError
        let operation: FinishOperation?

        var recovery: Recovery {
            switch (reason, operation) {
            case (.empty, _), (.tooLarge, _): .correctInput
            case (.newerVersion, _): .updateApplication
            case (.conflict, .some), (.staleDraft, .some), (.missing, .some): .saveAsNew
            default: .retry
            }
        }

        var canSaveAsNew: Bool { recovery == .saveAsNew || operation == .saveAsNew }
    }

    private let store: any DraftEditing
    private(set) var draft: Draft
    private(set) var phase: Phase = .editing
    private(set) var failure: Failure?
    private(set) var bodyRevision = 0

    init(draft: Draft, store: any DraftEditing) {
        self.store = store
        self.draft = draft
    }

    var title: String {
        get { draft.title }
        set {
            guard phase == .editing else { return }
            draft.title = newValue
        }
    }

    var body: String {
        get { draft.body }
        set {
            guard phase == .editing, !SnippetText.hasSameBytes(newValue, draft.body) else { return }
            draft.body = newValue
            bodyRevision += 1
        }
    }

    var hasBody: Bool { SnippetText.hasBody(body) }
    var canSave: Bool { hasBody && phase == .editing }

    func insertVariable(named name: VariableName, at selection: NSRange?) -> NSRange? {
        guard phase == .editing else { return nil }
        let position = selection ?? NSRange(location: body.utf16.count, length: 0)
        guard let replacementRange = Range(position, in: body) else { return nil }
        var text = body
        text.replaceSubrange(replacementRange, with: name.marker)
        body = text
        return NSRange(location: position.location + name.marker.utf16.count, length: 0)
    }

    func persist(_ snapshot: Draft) async {
        guard phase == .editing, draft.checkpoint.belongsToSameSession(as: snapshot.checkpoint) else { return }
        do {
            try await store.updateDraft(snapshot)
        } catch {
            guard phase == .editing, snapshot.checkpoint == draft.checkpoint else { return }
            failure = Failure(reason: error as? StoreError ?? .database, operation: nil)
        }
    }

    func finish(_ operation: FinishOperation) async -> Bool {
        guard phase == .editing, !Task.isCancelled else { return false }
        let input = draft
        phase = .finishing(operation)
        failure = nil
        do {
            try await commit(input, operation: operation)
            phase = .finished
            return true
        } catch {
            failure = Failure(reason: error as? StoreError ?? .database, operation: operation)
            phase = .editing
            return false
        }
    }

    private func commit(_ input: Draft, operation: FinishOperation) async throws {
        switch operation {
        case .keep: try await store.keepDraft(input)
        case .discard: try await store.discardDraft(input)
        case .save: try await store.save(input, mode: .save)
        case .saveAsNew: try await store.save(input, mode: .saveAsNew)
        }
    }
}
