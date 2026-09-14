import Foundation
import Observation
import Tasking

@MainActor @Observable
final class EditorModel {
    private(set) var draft: Draft
    private(set) var busy = false
    private(set) var finished = false
    var error: String?
    private(set) var conflict = false
    private let store: SnippetStore
    @ObservationIgnored private let draftTasks = ViewTaskStore()
    private static let persistDraft: ActionID = "editor.persistDraft"

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
        let store = store
        draftTasks.start(id: Self.persistDraft, lifetime: .screenBound, policy: .allowConcurrent) { [weak self] _ in
            // Every admitted write may finish; sequence checks in SQLite select the newest one.
            do { try await store.updateDraft(snapshot) }
            catch {
                if let self, !finished { self.error = "下書きを保存できませんでした。\n" + error.localizedDescription }
            }
        }
    }

    func waitForDraftWrites() async { await draftTasks.waitForIdle() }

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
