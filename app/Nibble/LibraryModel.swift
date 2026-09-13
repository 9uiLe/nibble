import SwiftUI
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: SnippetStore
    var query = ""
    var filter = LibraryFilter.all
    private(set) var items: [SnippetSummary] = []
    private(set) var drafts: [Draft] = []
    private(set) var loading = true
    private(set) var hasMore = false
    var error: String?
    var editor: Draft?
    var notice: String?
    var undoID: UUID?
    var feedback = 0
    var limit = 100
    private var request = UUID()
    private var opening = false
    private var noticeTask: Task<Void, Never>?

    init(store: SnippetStore = .shared) { self.store = store }

    func refresh() async {
        let token = UUID()
        request = token
        let query = query, filter = filter, limit = limit
        loading = true
        defer { if request == token { loading = false } }
        do {
            let values = try await store.search(query, filter: filter, limit: limit + 1)
            let drafts = try await store.drafts()
            try Task.checkCancellation()
            guard request == token else { return }
            self.items = Array(values.prefix(limit))
            self.hasMore = values.count > limit
            self.drafts = drafts
            error = nil
        } catch is CancellationError { }
        catch { if request == token { self.error = error.localizedDescription } }
    }

    func open(id: UUID? = nil) {
        guard editor == nil, !opening else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                if let id, let existing = drafts.first(where: { $0.snippetID == id }) { editor = existing }
                else { editor = try await store.beginDraft(snippetID: id) }
            } catch { self.error = error.localizedDescription }
        }
    }

    func copy(_ id: UUID) {
        Task {
            do {
                let snippet = try await store.snippet(id)
                guard !snippet.deleted else { throw StoreError.missing }
                UIPasteboard.general.setItems([["public.utf8-plain-text": snippet.body]], options: [.localOnly: true])
                feedback += 1
                announce("コピーしました")
            } catch { self.error = error.localizedDescription }
        }
    }

    func pin(_ item: SnippetSummary) {
        Task {
            do { try await store.setPinned(!item.pinned, id: item.id); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }

    func delete(_ id: UUID) {
        Task {
            do {
                try await store.setDeleted(true, id: id)
                await refresh()
                announce("削除しました", undo: id)
            } catch { self.error = error.localizedDescription }
        }
    }

    func restore(_ id: UUID) {
        Task {
            do {
                try await store.setDeleted(false, id: id)
                await refresh()
                announce("元に戻しました")
            } catch { self.error = error.localizedDescription }
        }
    }

    func permanentlyDelete(_ id: UUID) {
        Task {
            do {
                try await store.permanentlyDelete(id)
                await refresh()
                announce("完全に削除しました")
            } catch { self.error = error.localizedDescription }
        }
    }

    private func announce(_ text: String, undo: UUID? = nil) {
        noticeTask?.cancel()
        notice = text
        undoID = undo
        UIAccessibility.post(notification: .announcement, argument: text)
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(undo == nil ? 2 : 6)) }
            catch { return }
            self?.notice = nil
            self?.undoID = nil
        }
    }
}
