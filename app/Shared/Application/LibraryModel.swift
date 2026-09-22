import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private let store: any LibraryStorage
    private let effects: any LibraryEffects
    private let usageRecorder: any SnippetUsageRecording
    private let now: () -> Date
    private(set) var evaluatedAt: Date
    private struct PendingUse {
        enum State { case pending, recording, failed(StoreError) }
        let use: SnippetUse
        var state: State = .pending
        var failure: StoreError? {
            if case .failed(let message) = state { return message }
            return nil
        }
    }
    private var pendingUses: [PendingUse] = []
    enum EditorSource { case new, snippet(UUID), draft(UUID) }

    /// A visit to a visible surface. Leaving invalidates even work that finishes after returning.
    struct NoticeContext: Equatable {
        let id = UUID()
        let isPresented: Bool
    }
    private(set) var noticeContext = NoticeContext(isPresented: true)
    private let noticeSleep: (ContinuousClock.Instant) async throws -> Void
    private var noticeDeadline: ContinuousClock.Instant?
    private(set) var restoringIDs: Set<UUID> = []

    struct Notice: Identifiable, Equatable {
        enum Origin: Equatable { case library, search, trash }
        let id = UUID()
        let origin: Origin
        enum Result: Equatable {
            case copied, deleted(SnippetSummary), restored(SnippetSummary), permanentlyDeleted(SnippetSummary)
        }
        let result: Result
        var undoID: UUID? {
            if case .deleted(let item) = result { return item.id }
            return nil
        }
        var duration: Duration { undoID == nil ? .seconds(2) : .seconds(6) }
    }

    struct Failure: Equatable {
        enum Operation: Equatable { case load, open, copy, pin, delete, restore, permanentlyDelete, notice, recordUse }
        enum Recovery: Equatable { case reload, dismiss, retryUsage, retryRestore(UUID) }
        let operation: Operation
        let reason: StoreError
        let recovery: Recovery
    }

    private var content: LibraryReadState
    let surface: LibrarySurface
    private let libraryReader: any LibraryReading
    private let libraryOpener: any LibraryOpening
    var request: LibraryRequest { content.request }
    var snapshot: LibraryReadState.Snapshot? { content.snapshot }
    var page: LibraryPage { snapshot?.page ?? LibraryPage() }
    var contentRequest: LibraryRequest { content.contentRequest }
    var contentIsCurrent: Bool { content.contentIsCurrent }
    var loading: Bool { content.loading }
    var loadingInterrupted: Bool { content.interrupted }
    var readDemand: LibraryRequest? { content.demand }
    var refreshOnAppearance: Bool { content.refreshOnAppearance }
    private(set) var notice: Notice?
    private(set) var feedback = 0
    private(set) var mutationRevision = 0
    private var operationFailure: Failure?
    var failure: Failure? {
        if let operationFailure { return operationFailure }
        if let reason = pendingUses.lazy.compactMap(\.failure).first {
            return Failure(operation: .recordUse, reason: reason, recovery: .retryUsage)
        }
        guard let error = content.error else { return nil }
        return Failure(operation: .load, reason: error as? StoreError ?? .database, recovery: .reload)
    }

    var editor: Draft?
    private var opening: UUID?

    var query: String {
        get { request.query }
        set { content.search(newValue) }
    }
    var filter: LibraryFilter {
        get { request.filter }
        set { content.select(newValue) }
    }
    var items: [SnippetSummary] { page.items }
    var drafts: [DraftSummary] { page.drafts }
    var hasMore: Bool { contentIsCurrent && page.hasMore }

    func unusedSince(for item: SnippetSummary) -> Date? {
        guard contentRequest.filter != .trash,
              let usage = item.usage, usage.isDeletionCandidate(at: evaluatedAt) else { return nil }
        return usage.lastUsedAt
    }

    func showMore() { content.showMore() }
    func dismissFailure() { operationFailure = nil }

    init(store: any LibraryStorage, effects: any LibraryEffects, surface: LibrarySurface = .library,
         libraryReader: (any LibraryReading)? = nil, libraryOpener: (any LibraryOpening)? = nil,
         usageRecorder: (any SnippetUsageRecording)? = nil, now: @escaping () -> Date = Date.init,
         noticeSleep: @escaping (ContinuousClock.Instant) async throws -> Void = { try await ContinuousClock().sleep(until: $0) }) {
        self.store = store
        self.surface = surface
        content = LibraryReadState(surface: surface)
        self.effects = effects
        self.libraryReader = libraryReader ?? store
        self.libraryOpener = libraryOpener ?? store
        self.usageRecorder = usageRecorder ?? store
        self.now = now
        self.noticeSleep = noticeSleep
        evaluatedAt = now()
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
        catch { if self.notice?.id == id { report(.notice, error) } }
    }

    /// An explicit recovery reload clears the acknowledged operation failure.
    func reload() async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        await refresh()
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        let read = content.begin()
        defer { content.end(read) }
        do {
            let pages = try await libraryReader.libraries(read.requests)
            try Task.checkCancellation()
            if try content.accept(pages, from: read) { evaluatedAt = now() }
        } catch {
            let outcome: LibraryReadState.Outcome = Task.isCancelled || error is CancellationError ? .cancelled : .failed(error)
            content.complete(outcome, from: read)
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
            setNoticePresentation(false)
            editor = draft
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, opening == requestID else { return }
            report(.open, error)
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
            announce(.copied, context: context)
            pendingUses.append(PendingUse(use: use))
            await persistUse(use)
            await refresh()
        } catch is CancellationError { }
        catch { if !Task.isCancelled { report(.copy, error) } }
    }

    /// Retries the completed copy's record, never the clipboard effect.
    func retryUsageRecording() async {
        guard !Task.isCancelled else { return }
        for pending in pendingUses { await persistUse(pending.use) }
        await refresh()
    }

    private func persistUse(_ use: SnippetUse) async {
        guard let index = pendingUses.firstIndex(where: { $0.use.id == use.id }) else { return }
        if case .recording = pendingUses[index].state { return }
        pendingUses[index].state = .recording
        do {
            try await usageRecorder.recordUse(use)
            mutationRevision += 1
            pendingUses.removeAll { $0.use.id == use.id }
        } catch StoreError.missing {
            pendingUses.removeAll { $0.use.id == use.id }
            operationFailure = Failure(operation: .recordUse, reason: .missing, recovery: .dismiss)
        } catch {
            if let index = pendingUses.firstIndex(where: { $0.use.id == use.id }) {
                pendingUses[index].state = .failed(error as? StoreError ?? .database)
            }
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
        catch { report(.pin, error) }
    }

    func delete(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled else { return }
        let context = context ?? noticeContext
        operationFailure = nil
        do {
            let result = try await store.mutate(.delete, id: id)
            mutationRevision += 1
            announce(.deleted(result), context: context)
            await refresh()
        } catch { report(.delete, error) }
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
            announce(.restored(result), context: context)
            await refresh()
        } catch {
            operationFailure = Failure(operation: .restore, reason: error as? StoreError ?? .database,
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
            announce(.permanentlyDeleted(result), context: context)
            await refresh()
        } catch { report(.permanentlyDelete, error) }
    }

    private func report(_ operation: Failure.Operation, _ error: Error) {
        operationFailure = Failure(operation: operation, reason: error as? StoreError ?? .database,
                                   recovery: error as? StoreError == .missing ? .reload : .dismiss)
    }

    private func announce(_ result: Notice.Result, context: NoticeContext) {
        guard context == noticeContext, context.isPresented else { return }
        let value = Notice(origin: surface.noticeOrigin, result: result)
        notice = value
        noticeDeadline = nil
        feedback += 1
        effects.announce(value)
    }
}
