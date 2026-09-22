import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private let store: any LibraryStorage
    private let effects: any LibraryEffects
    private let usageRecorder: any SnippetUsageRecording
    private let now: () -> Date
    private(set) var evaluatedAt: Date
    private var pendingUses: [SnippetUse] = []
    private var recordingUses: Set<UUID> = []
    private var usageErrors: [UUID: String] = [:]
    enum EditorSource { case new, snippet(UUID), draft(UUID) }

    /// A visit to a visible surface. Leaving invalidates even work that finishes after returning.
    struct NoticeContext: Equatable {
        let id = UUID()
        let isPresented: Bool
    }
    private(set) var noticeContext = NoticeContext(isPresented: true)
    private let noticeOrigin: Notice.Origin
    private let noticeSleep: (ContinuousClock.Instant) async throws -> Void
    private var noticeDeadline: ContinuousClock.Instant?
    private(set) var restoringIDs: Set<UUID> = []

    struct Notice: Identifiable, Equatable {
        enum Origin: Equatable { case library, search, trash }
        let id = UUID()
        let origin: Origin
        let message: String
        let subject: String?
        let undoID: UUID?
        var duration: Duration { undoID == nil ? .seconds(2) : .seconds(6) }
        var announcement: String { subject.map { "\($0)、\(message)" } ?? message }
    }

    struct Failure: Equatable {
        enum Recovery: Equatable { case reload, dismiss, retryUsage, retryRestore(UUID) }
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
    let retainsFilters: Bool
    private var filterSnapshots: [LibraryFilter: Snapshot] = [:]
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
    private(set) var mutationRevision = 0
    private var operationFailure: Failure?
    var failure: Failure? {
        if let operationFailure { return operationFailure }
        if let pending = pendingUses.first(where: { usageErrors[$0.id] != nil }) {
            return Failure(title: "コピー済みですが、回数と日時を記録できませんでした",
                           message: "本文は貼り付けて使えます。下のボタンで、コピー回数と最後にコピーした日時の記録だけをやり直せます。\n" + (usageErrors[pending.id] ?? ""),
                           recovery: .retryUsage)
        }
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
            if retainsFilters, let retained = filterSnapshots[newValue], retained.request.query == request.query {
                request = retained.request
                snapshot = retained
                completedRead = (request, .loaded)
            } else {
                request = LibraryRequest(query: request.query, filter: newValue)
            }
        }
    }
    var items: [SnippetSummary] { page.items }
    var drafts: [DraftSummary] { page.drafts }
    var hasMore: Bool { contentIsCurrent && page.hasMore }

    func showMore() { request = request.expanded }
    func dismissFailure() { operationFailure = nil }

    init(store: any LibraryStorage, effects: any LibraryEffects, filter: LibraryFilter = .all, retainsFilters: Bool = false,
         libraryReader: (any LibraryReading)? = nil, libraryOpener: (any LibraryOpening)? = nil,
         usageRecorder: (any SnippetUsageRecording)? = nil, now: @escaping () -> Date = Date.init,
         noticeOrigin: Notice.Origin = .library,
         noticeSleep: @escaping (ContinuousClock.Instant) async throws -> Void = { try await ContinuousClock().sleep(until: $0) }) {
        self.store = store
        self.retainsFilters = retainsFilters
        self.effects = effects
        self.libraryReader = libraryReader ?? store
        self.libraryOpener = libraryOpener ?? store
        self.usageRecorder = usageRecorder ?? store
        self.now = now
        self.noticeOrigin = filter == .trash ? .trash : noticeOrigin
        self.noticeSleep = noticeSleep
        evaluatedAt = now()
        request = LibraryRequest(filter: filter)
    }

    func clearNotice() {
        notice = nil
        noticeDeadline = nil
    }

    func setNoticePresentation(_ isPresented: Bool) {
        guard noticeContext.isPresented != isPresented else { return }
        noticeContext = NoticeContext(isPresented: isPresented)
        clearNotice()
    }

    func expireNotice(id: UUID) async {
        guard let notice, notice.id == id else { return }
        // Start when the UI displays the notice; remounts retain the original deadline.
        let deadline = noticeDeadline ?? ContinuousClock.now.advanced(by: notice.duration)
        noticeDeadline = deadline
        do {
            try await noticeSleep(deadline)
            try Task.checkCancellation()
            guard self.notice?.id == id else { return }
            clearNotice()
        } catch is CancellationError { }
        catch { if self.notice?.id == id { report("通知を更新できませんでした", error) } }
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
            let requests: [LibraryRequest]
            if retainsFilters && requested.filter != .trash {
                requests = [LibraryFilter.all, .pinned, .drafts].map { filter in
                    LibraryRequest(query: requested.query, filter: filter,
                                   limit: filter == requested.filter ? requested.limit
                                       : filterSnapshots[filter]?.request.limit ?? LibraryRequest.pageSize)
                }
            } else { requests = [requested] }
            let pages = try await libraryReader.libraries(requests)
            try Task.checkCancellation()
            guard activeRefresh == token, canAdoptRead(requested) else { return }
            guard pages.count == requests.count else { throw StoreError.unavailable }
            let snapshots = zip(requests, pages).map { Snapshot(request: $0, page: $1) }
            if retainsFilters {
                filterSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.request.filter, $0) })
            }
            snapshot = snapshots.first { $0.request.filter == request.filter }
            evaluatedAt = now()
            completedRead = (request, .loaded)
        } catch {
            guard activeRefresh == token, canAdoptRead(requested) else { return }
            let outcome: ReadOutcome = Task.isCancelled || error is CancellationError ? .cancelled
                : .failed(Failure(title: "一覧を読み込めませんでした",
                                  message: recoveryMessage(error, retry: "「一覧を再読み込み」を押してください。"), recovery: .reload))
            completedRead = (request, outcome)
        }
    }

    private func canAdoptRead(_ requested: LibraryRequest) -> Bool {
        if retainsFilters && requested.filter != .trash && request.filter != .trash {
            return request.query == requested.query
                && (request.filter != requested.filter || request.limit == requested.limit)
        }
        return request == requested
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
            setNoticePresentation(false)
            editor = draft
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, opening == requestID else { return }
            report("編集を始められませんでした", error)
        }
    }

    func copy(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled else { return }
        let context = context ?? noticeContext
        operationFailure = nil
        do {
            try Task.checkCancellation()
            let body = try await store.savedBody(id)
            try Task.checkCancellation()
            effects.copy(body)
            let use = SnippetUse(id: UUID(), snippetID: id, completedAt: now())
            announce("コピーしました", context: context)
            pendingUses.append(use)
            await persistUse(use)
            await refresh()
        } catch is CancellationError { }
        catch { if !Task.isCancelled { report("コピーできませんでした", error) } }
    }

    /// Retries the completed copy's record, never the clipboard effect.
    func retryUsageRecording() async {
        guard !Task.isCancelled else { return }
        for use in pendingUses { await persistUse(use) }
        await refresh()
    }

    private func persistUse(_ use: SnippetUse) async {
        guard recordingUses.insert(use.id).inserted else { return }
        defer { recordingUses.remove(use.id) }
        do {
            try await usageRecorder.recordUse(use)
            mutationRevision += 1
            pendingUses.removeAll { $0.id == use.id }
            usageErrors[use.id] = nil
        } catch StoreError.missing {
            pendingUses.removeAll { $0.id == use.id }
            usageErrors[use.id] = nil
            operationFailure = Failure(title: "コピー済みですが、回数と日時を記録できませんでした",
                                       message: "本文は貼り付けて使えます。項目が完全に削除されたため、コピー回数と日時は記録できません。「閉じる」でこの案内を閉じてください。",
                                       recovery: .dismiss)
        } catch {
            usageErrors[use.id] = recoveryMessage(error, retry: "")
        }
    }

    func pin(_ item: SnippetSummary) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        do {
            try await store.setPinned(!item.pinned, id: item.id)
            mutationRevision += 1
            await refresh()
        }
        catch { report("ピン留めを変更できませんでした", error) }
    }

    func delete(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled else { return }
        let context = context ?? noticeContext
        operationFailure = nil
        do {
            let result = try await store.mutate(.delete, id: id)
            mutationRevision += 1
            announce("削除しました", subject: result.subject, undo: id, context: context)
            await refresh()
        } catch { report("削除できませんでした", error) }
    }

    func undoNotice(_ id: UUID, context: NoticeContext? = nil) async {
        guard let notice, notice.id == id, let target = notice.undoID else { return }
        await restore(target, context: context)
        if operationFailure != nil, self.notice?.id == id { clearNotice() }
    }

    func restore(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled, restoringIDs.insert(id).inserted else { return }
        defer { restoringIDs.remove(id) }
        let context = context ?? noticeContext
        operationFailure = nil
        do {
            let result = try await store.mutate(.restore, id: id)
            mutationRevision += 1
            announce("元に戻しました", subject: result.subject, context: context)
            await refresh()
        } catch {
            operationFailure = Failure(title: "復元できませんでした",
                                       message: recoveryMessage(error, retry: error as? StoreError == .missing
                                           ? "「一覧を再読み込み」を押してください。" : "「もう一度復元する」を押してください。"),
                                       recovery: error as? StoreError == .missing ? .reload : .retryRestore(id))
        }
    }

    func permanentlyDelete(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled else { return }
        let context = context ?? noticeContext
        operationFailure = nil
        do {
            let result = try await store.mutate(.permanentlyDelete, id: id)
            mutationRevision += 1
            announce("完全に削除しました", subject: result.subject, context: context)
            await refresh()
        } catch { report("完全に削除できませんでした", error) }
    }

    private func report(_ title: String, _ error: Error) {
        operationFailure = Failure(title: title, message: recoveryMessage(error, retry: error as? StoreError == .missing
                                       ? "「一覧を再読み込み」を押してください。" : "この案内を閉じて、もう一度操作してください。"),
                                   recovery: error as? StoreError == .missing ? .reload : .dismiss)
    }

    private func recoveryMessage(_ error: Error, retry: String) -> String {
        if error as? StoreError == .newerVersion {
            return "nibbleを最新バージョンに更新してから、もう一度操作してください。"
        }
        return ((error as? StoreError)?.localizedDescription ?? "保存データを読み書きできませんでした。") + retry
    }

    private func announce(_ text: String, subject: String? = nil, undo: UUID? = nil, context: NoticeContext) {
        guard context == noticeContext, context.isPresented else { return }
        let value = Notice(origin: noticeOrigin, message: text, subject: subject, undoID: undo)
        notice = value
        noticeDeadline = nil
        feedback += 1
        effects.announce(value.announcement)
    }
}
