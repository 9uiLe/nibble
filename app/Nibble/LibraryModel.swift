import SwiftUI
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: SnippetStore
    enum EditorSource { case new, snippet(UUID), draft(UUID) }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undoID: UUID?
        var duration: Duration { undoID == nil ? .seconds(2) : .seconds(6) }
    }

    private(set) var request = LibraryRequest()
    private(set) var page = LibraryPage()
    private(set) var loading = true
    private(set) var notice: Notice?
    private(set) var feedback = 0
    var error: String?
    var editor: Draft?
    private var refreshID = UUID()
    private var opening = false

    var query: String {
        get { request.query }
        set {
            guard !SnippetText.hasSameBytes(newValue, request.query) else { return }
            request = LibraryRequest(query: newValue, filter: request.filter)
        }
    }
    var filter: LibraryFilter {
        get { request.filter }
        set {
            guard newValue != request.filter else { return }
            request = LibraryRequest(query: request.query, filter: newValue)
        }
    }
    var items: [SnippetSummary] { page.items }
    var drafts: [DraftSummary] { page.drafts }
    var hasMore: Bool { page.hasMore }

    func showMore() { request = request.expanded }

    init(store: SnippetStore = .shared, filter: LibraryFilter = .all) {
        self.store = store
        request = LibraryRequest(filter: filter)
    }

    func clearNotice() { notice = nil }

    func expireNotice(id: UUID) async {
        guard let notice, notice.id == id else { return }
        do {
            try await Task.sleep(for: notice.duration)
            try Task.checkCancellation()
            guard self.notice?.id == id else { return }
            clearNotice()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    func refresh() async {
        let token = UUID()
        refreshID = token
        let requested = request
        loading = true
        defer { if refreshID == token { loading = false } }
        do {
            let page = try await store.library(requested)
            try Task.checkCancellation()
            guard refreshID == token, request == requested else { return }
            self.page = page
            error = nil
        } catch is CancellationError { }
        catch {
            if refreshID == token, request == requested { self.error = error.localizedDescription }
        }
    }

    func open(_ source: EditorSource = .new) async {
        guard !Task.isCancelled, editor == nil, !opening else { return }
        opening = true
        defer { opening = false }
        do {
            // Read at the time of opening; library rows deliberately contain no editable snapshot.
            let draft: Draft
            switch source {
            case .new: draft = try await store.beginDraft()
            case .snippet(let id): draft = try await store.editingDraft(for: id)
            case .draft(let id): draft = try await store.draft(id)
            }
            if case .new = source { filter = .all }
            editor = draft
        } catch { self.error = error.localizedDescription }
    }

    func copy(_ id: UUID) async {
        do {
            try Task.checkCancellation()
            let snippet = try await store.snippet(id)
            try Task.checkCancellation()
            guard !snippet.deleted else { throw StoreError.missing }
            UIPasteboard.general.setItems([["public.utf8-plain-text": snippet.body]], options: [.localOnly: true])
            feedback += 1
            announce("コピーしました")
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    func pin(_ item: SnippetSummary) async {
        guard !Task.isCancelled else { return }
        do { try await store.setPinned(!item.pinned, id: item.id); await refresh() }
        catch { self.error = error.localizedDescription }
    }

    func delete(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        do {
            try await store.setDeleted(true, id: id)
            await refresh()
            announce("削除しました", undo: id)
        } catch { self.error = error.localizedDescription }
    }

    func restore(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        do {
            try await store.setDeleted(false, id: id)
            await refresh()
            announce("元に戻しました")
        } catch { self.error = error.localizedDescription }
    }

    func permanentlyDelete(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        do {
            try await store.permanentlyDelete(id)
            await refresh()
            announce("完全に削除しました")
        } catch { self.error = error.localizedDescription }
    }

    private func announce(_ text: String, undo: UUID? = nil) {
        notice = Notice(message: text, undoID: undo)
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
