import SwiftUI
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: SnippetStore
    enum EditorSource { case new, snippet(UUID), draft(UUID) }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let subject: String?
        let undoID: UUID?
        var duration: Duration { undoID == nil ? .seconds(2) : .seconds(6) }
        var announcement: String { subject.map { "\($0)、\(message)" } ?? message }
    }

    struct Failure: Equatable {
        enum Recovery: Equatable { case reload, dismiss }
        let title: String
        let message: String
        let recovery: Recovery
    }

    private(set) var request = LibraryRequest()
    private(set) var page = LibraryPage()
    private(set) var loading = true
    private(set) var notice: Notice?
    private(set) var feedback = 0
    private var loadFailure: Failure?
    private var operationFailure: Failure?
    var failure: Failure? { operationFailure ?? loadFailure }
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
    func dismissFailure() { operationFailure = nil }

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
        catch { report("通知を更新できませんでした", error) }
    }

    /// An explicit recovery reload clears the acknowledged operation failure.
    func reload() async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        await refresh()
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
            loadFailure = nil
        } catch is CancellationError { }
        catch {
            if refreshID == token, request == requested {
                loadFailure = Failure(title: "一覧を読み込めませんでした", message: error.localizedDescription, recovery: .reload)
            }
        }
    }

    func open(_ source: EditorSource = .new) async {
        guard !Task.isCancelled, editor == nil, !opening else { return }
        opening = true
        operationFailure = nil
        defer { opening = false }
        do {
            // Read at the time of opening; rows contain no editable snapshot.
            let draft: Draft
            switch source {
            case .new: draft = try await store.beginDraft()
            case .snippet(let id): draft = try await store.editingDraft(for: id)
            case .draft(let id): draft = try await store.draft(id)
            }
            if case .new = source { filter = .all }
            editor = draft
        } catch { report("編集を始められませんでした", error) }
    }

    func copy(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            try Task.checkCancellation()
            let snippet = try await store.snippet(id)
            try Task.checkCancellation()
            guard !snippet.deleted else { throw StoreError.missing }
            UIPasteboard.general.setItems([["public.utf8-plain-text": snippet.body]], options: [.localOnly: true])
            feedback += 1
            announce("コピーしました")
        } catch is CancellationError { }
        catch { report("コピーできませんでした", error) }
    }

    func pin(_ item: SnippetSummary) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do { try await store.setPinned(!item.pinned, id: item.id); await refresh() }
        catch { report("ピン留めを変更できませんでした", error) }
    }

    func delete(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            let name = try await subject(id)
            try await store.setDeleted(true, id: id)
            await refresh()
            announce("削除しました", subject: name, undo: id)
        } catch { report("削除できませんでした", error) }
    }

    func restore(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            let name = try await subject(id)
            try await store.setDeleted(false, id: id)
            await refresh()
            announce("元に戻しました", subject: name)
        } catch { report("復元できませんでした", error) }
    }

    func permanentlyDelete(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            let name = try await subject(id)
            try await store.permanentlyDelete(id)
            await refresh()
            announce("完全に削除しました", subject: name)
        } catch { report("完全に削除できませんでした", error) }
    }

    private func subject(_ id: UUID) async throws -> String {
        if let item = items.first(where: { $0.id == id }) { return item.displayTitle }
        return try await store.summary(id).displayTitle
    }

    private func report(_ title: String, _ error: Error) {
        operationFailure = Failure(title: title, message: error.localizedDescription,
                                   recovery: error as? StoreError == .missing ? .reload : .dismiss)
    }

    private func announce(_ text: String, subject: String? = nil, undo: UUID? = nil) {
        let value = Notice(message: text, subject: subject, undoID: undo)
        notice = value
        UIAccessibility.post(notification: .announcement, argument: value.announcement)
    }
}
