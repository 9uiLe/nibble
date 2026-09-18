import Foundation
import Observation

/// Draft lookup is separate from presentation so late database results can be discarded.
protocol LibraryOpening: Sendable {
    func beginDraft(snippetID: UUID?, body: String) async throws -> Draft
    func editingDraft(for id: UUID) async throws -> Draft
    func draft(_ id: UUID) async throws -> Draft
}

extension SnippetStore: LibraryOpening { }

@MainActor @Observable
final class LibraryModel {
    let store: SnippetStore
    private let effects: any LibraryEffects
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
    struct Snapshot {
        let request: LibraryRequest
        let page: LibraryPage
    }

    private(set) var snapshot: Snapshot?
    private enum ReadOutcome { case loaded, cancelled, failed(Failure) }
    private var completedRead: (request: LibraryRequest, outcome: ReadOutcome)?
    private var activeRefresh: UUID?
    private let libraryReader: any LibraryReading
    private let libraryOpener: any LibraryOpening
    var page: LibraryPage { snapshot?.page ?? LibraryPage() }
    var contentRequest: LibraryRequest { snapshot?.request ?? request }
    var contentIsCurrent: Bool {
        guard let snapshot else { return false }
        return snapshot.request.filter == request.filter
            && snapshot.request.query == request.query
    }
    // Selection changes synchronously invalidate completion, before the UI starts its task.
    var loading: Bool { activeRefresh != nil || completedRead?.request != request }
    var loadingInterrupted: Bool {
        guard !loading, completedRead?.request == request,
              case .cancelled = completedRead?.outcome else { return false }
        return true
    }
    private(set) var notice: Notice?
    private(set) var feedback = 0
    private var operationFailure: Failure?
    var failure: Failure? {
        if let operationFailure { return operationFailure }
        if completedRead?.request == request, case .failed(let failure) = completedRead?.outcome { return failure }
        return nil
    }
    var editor: Draft?
    private var opening: UUID?

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
    var hasMore: Bool { contentIsCurrent && page.hasMore }

    func showMore() { request = request.expanded }
    func dismissFailure() { operationFailure = nil }

    init(store: SnippetStore, effects: any LibraryEffects, filter: LibraryFilter = .all,
         libraryReader: (any LibraryReading)? = nil, libraryOpener: (any LibraryOpening)? = nil) {
        self.store = store
        self.effects = effects
        self.libraryReader = libraryReader ?? store
        self.libraryOpener = libraryOpener ?? store
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
        guard !Task.isCancelled else { return }
        let token = UUID()
        activeRefresh = token
        let requested = request
        defer { if activeRefresh == token { activeRefresh = nil } }
        do {
            let page = try await libraryReader.library(requested)
            try Task.checkCancellation()
            guard activeRefresh == token, request == requested else { return }
            snapshot = Snapshot(request: requested, page: page)
            completedRead = (requested, .loaded)
        } catch {
            guard activeRefresh == token, request == requested else { return }
            let outcome: ReadOutcome = Task.isCancelled || error is CancellationError ? .cancelled
                : .failed(Failure(title: "一覧を読み込めませんでした",
                                  message: error.localizedDescription, recovery: .reload))
            completedRead = (requested, outcome)
        }
    }

    /// Invalidates only this owner's presentation request, without cancelling accepted writes.
    func cancelOpening(id: UUID) {
        if opening == id { opening = nil }
    }

    func open(_ source: EditorSource = .new, requestID: UUID = UUID()) async {
        guard !Task.isCancelled, editor == nil, opening == nil else { return }
        opening = requestID
        operationFailure = nil
        defer { if opening == requestID { opening = nil } }
        do {
            // Read at the time of opening; rows contain no editable snapshot.
            let draft: Draft
            switch source {
            case .new: draft = try await libraryOpener.beginDraft(snippetID: nil, body: "")
            case .snippet(let id): draft = try await libraryOpener.editingDraft(for: id)
            case .draft(let id): draft = try await libraryOpener.draft(id)
            }
            guard !Task.isCancelled, opening == requestID else {
                // No user input exists for a new, unpresented draft. Existing drafts stay intact.
                if case .new = source { try? await store.keepDraft(draft) }
                return
            }
            if case .new = source { filter = .all }
            editor = draft
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, opening == requestID else { return }
            report("編集を始められませんでした", error)
        }
    }

    func copy(_ id: UUID) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            try Task.checkCancellation()
            let snippet = try await store.snippet(id)
            try Task.checkCancellation()
            guard !snippet.deleted else { throw StoreError.missing }
            effects.copy(snippet.body)
            feedback += 1
            announce("コピーしました")
        } catch is CancellationError { }
        catch { if !Task.isCancelled { report("コピーできませんでした", error) } }
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
        effects.announce(value.announcement)
    }
}
