import Foundation
import Observation

@MainActor @Observable
final class EditorModel {
    enum Phase: Equatable { case editing, finishing(FinishOperation), finished }
    enum FinishOperation: Equatable {
        case save, saveAsNew, keep, discard
        var progressTitle: String {
            switch self {
            case .save, .saveAsNew: "保存中"
            case .keep: "下書きを保存中"
            case .discard: "下書きを破棄中"
            }
        }
    }

    struct Failure: Equatable {
        let message: String
        let canSaveAsNew: Bool
    }

    private(set) var draft: Draft
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
        set { if phase == .editing { draft.body = newValue } }
    }

    var hasBody: Bool { !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canSave: Bool { phase == .editing && hasBody }

    func persist(_ snapshot: Draft) async {
        guard phase == .editing, snapshot.id == draft.id else { return }
        // An admitted write completes after cancellation. SQL ignores older and removed snapshots.
        do { try await store.updateDraft(snapshot) }
        catch {
            // A previous input's failure must not overwrite a newer input or a finish result.
            if phase == .editing && snapshot.sequence == draft.sequence {
                failure = Failure(message: failureMessage(error, operation: nil),
                                  canSaveAsNew: false)
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
            let storeError = error as? StoreError
            failure = Failure(message: failureMessage(error, operation: operation),
                              canSaveAsNew: operation == .saveAsNew || storeError == .conflict || storeError == .staleDraft || storeError == .missing)
            return false
        }
    }

    private func failureMessage(_ error: Error, operation: FinishOperation?) -> String {
        let title: String
        let retry: String
        switch operation {
        case .save, .saveAsNew:
            title = "保存できませんでした。"
            retry = operation == .saveAsNew ? "「新しい項目として保存」をもう一度押してください。" : "「保存」をもう一度押してください。"
        case .keep:
            title = "下書きを保存できなかったため、閉じられませんでした。"
            retry = "「閉じる」をもう一度押してください。"
        case .discard:
            title = "下書きを破棄できませんでした。"
            retry = "「その他」から「下書きを破棄」をもう一度選んでください。"
        case nil:
            title = "下書きを自動保存できませんでした。"
            retry = "「保存」または「閉じる」を押して、もう一度保存してください。"
        }
        let reason = (error as? StoreError)?.localizedDescription ?? "保存データを読み書きできませんでした。"
        let recovery: String
        switch error as? StoreError {
        case .conflict, .staleDraft, .missing:
            recovery = operation == nil ? retry : "「新しい項目として保存」で、この画面の内容を別の項目に保存できます。"
        case .empty, .tooLarge:
            recovery = ""
        case .newerVersion:
            recovery = "入力をコピーして別の場所に控えてから、nibbleを更新してください。"
        default:
            recovery = retry
        }
        return title + "入力はこの画面に残っています。\n" + reason + recovery
    }
}
