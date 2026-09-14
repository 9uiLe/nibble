import Foundation
import Observation

@MainActor @Observable
final class EditorModel {
    private(set) var draft: Draft
    private(set) var busy = false
    private(set) var finished = false
    var error: String?
    private(set) var conflict = false
    private let store: SnippetStore

    init(draft: Draft, store: SnippetStore) {
        self.draft = draft
        self.store = store
    }

    var title: String {
        get { draft.title }
        set { draft.title = newValue; persistChange() }
    }

    var body: String {
        get { draft.body }
        set { draft.body = newValue; persistChange() }
    }

    var canSave: Bool { !busy && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func persistChange() {
        draft.sequence += 1
        let snapshot = draft
        Task {
            do { try await store.updateDraft(snapshot) }
            catch { if !finished { self.error = "下書きを保存できませんでした。\n" + error.localizedDescription } }
        }
    }

    func save(asNew: Bool = false) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await store.save(draft, asNew: asNew)
            finished = true
            return true
        } catch {
            conflict = (error as? StoreError) == .conflict
            self.error = error.localizedDescription
            return false
        }
    }

    func keepForLater() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            if (draft.title.isEmpty && draft.body.isEmpty) || (draft.snippetID != nil && draft.sequence == 0) {
                try await store.discardDraft(draft.id)
            }
            else { try await store.updateDraft(draft) }
            finished = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func discard() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await store.discardDraft(draft.id)
            finished = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
