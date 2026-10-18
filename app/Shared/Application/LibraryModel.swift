import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    enum EditorSource { case new, snippet(UUID), draft(UUID) }

    struct NoticeContext: Equatable {
        let id = UUID()
        let isPresented: Bool
    }

    struct Notice: Identifiable, Equatable {
        enum Origin: Equatable { case library, trash }
        enum Result: Equatable {
            case copied
            case deleted(SnippetSummary)
            case restored(SnippetSummary)
            case permanentlyDeleted(SnippetSummary)
        }
        let id = UUID()
        let origin: Origin
        let result: Result

        var undoID: UUID? {
            guard case .deleted(let item) = result else { return nil }
            return item.id
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

    struct VariableCopy: Identifiable {
        let id = UUID()
        let snippetID: UUID
        let title: String
        let template: SnippetVariables
        let context: NoticeContext
        let availability: FeatureAvailability
    }

    private struct CopyRecord {
        enum Status { case waiting, saving, failed(StoreError) }
        let use: SnippetUse
        var status: Status = .waiting
    }

    private struct MutationKey: Hashable {
        enum Kind: Hashable { case pin, delete, restore, permanentlyDelete }
        let kind: Kind
        let id: UUID
    }

    let surface: LibrarySurface
    private let store: any LibraryStorage
    private let effects: any LibraryEffects
    private let reader: any LibraryReading
    private let opener: any LibraryOpening
    private let recorder: any SnippetUsageRecording
    private let proIsActive: () -> Bool
    private let now: () -> Date
    private let noticeSleep: (ContinuousClock.Instant) async throws -> Void
    private var reads: LibraryReadState
    private var openingRequest: UUID?
    private var inFlightMutations: Set<MutationKey> = []
    private var copies: [UUID: CopyRecord] = [:]
    private var operationFailure: Failure?
    private var noticeDeadline: ContinuousClock.Instant?
    private(set) var noticeContext = NoticeContext(isPresented: true)
    private(set) var notice: Notice?
    private(set) var variableCopy: VariableCopy?
    private(set) var feedback = 0
    private(set) var mutationRevision = 0
    private(set) var evaluatedAt: Date
    private(set) var restoringIDs: Set<UUID> = []
    var editor: Draft?

    init(store: any LibraryStorage, effects: any LibraryEffects, surface: LibrarySurface = .library,
         libraryReader: (any LibraryReading)? = nil, libraryOpener: (any LibraryOpening)? = nil,
         usageRecorder: (any SnippetUsageRecording)? = nil, proIsActive: @escaping () -> Bool = { false },
         now: @escaping () -> Date = Date.init,
         noticeSleep: @escaping (ContinuousClock.Instant) async throws -> Void = { try await ContinuousClock().sleep(until: $0) }) {
        self.store = store
        self.effects = effects
        self.surface = surface
        reader = libraryReader ?? store
        opener = libraryOpener ?? store
        recorder = usageRecorder ?? store
        self.proIsActive = proIsActive
        self.now = now
        self.noticeSleep = noticeSleep
        reads = LibraryReadState(surface: surface)
        evaluatedAt = now()
    }

    var query: String {
        get { reads.query }
        set { reads.search(newValue) }
    }
    var filter: LibraryFilter {
        get { reads.selection }
        set { reads.select(newValue) }
    }
    var request: LibraryRequest { reads.request }
    var snapshot: LibraryReadState.Snapshot? { reads.snapshot }
    var page: LibraryPage { snapshot?.page ?? LibraryPage() }
    var items: [SnippetSummary] { page.items }
    var drafts: [DraftSummary] { page.drafts }
    var contentRequest: LibraryRequest { reads.contentRequest }
    var contentIsCurrent: Bool { reads.contentIsCurrent }
    var loading: Bool { reads.loading }
    var loadingInterrupted: Bool { reads.interrupted }
    var readDemand: LibraryRequest? { reads.demand }
    var refreshOnAppearance: Bool { reads.refreshOnAppearance }
    var isSearching: Bool { reads.isSearching }
    var hasMore: Bool { contentIsCurrent && page.hasMore }
    var includesDrafts: Bool { surface == .library && !isSearching && contentRequest.includesDrafts }
    var canShowAll: Bool { surface == .library && filter == .pinned && !isSearching }
    var contentIsEmpty: Bool { items.isEmpty && (!includesDrafts || drafts.isEmpty) }
    var showsEmptyState: Bool { contentIsCurrent && contentIsEmpty && !loading && !loadingInterrupted && failure == nil }

    var failure: Failure? {
        if let operationFailure { return operationFailure }
        for record in copies.values {
            if case .failed(let reason) = record.status {
                return Failure(operation: .recordUse, reason: reason, recovery: .retryUsage)
            }
        }
        guard let error = reads.error else { return nil }
        return Failure(operation: .load, reason: storeError(error), recovery: .reload)
    }

    func unusedSince(for item: SnippetSummary) -> Date? {
        guard contentRequest.filter != .trash, let usage = item.usage,
              usage.isDeletionCandidate(at: evaluatedAt) else { return nil }
        return usage.lastUsedAt
    }

    func showAll() { reads.showAll() }
    func showMore() { reads.showMore() }
    func dismissFailure() { operationFailure = nil }

    func refresh(includingCollections: Bool = false) async {
        await fetch(includingCollections: includingCollections, acceptsCancellation: true)
    }

    func reload() async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        await refresh(includingCollections: true)
    }

    private func fetch(includingCollections: Bool, acceptsCancellation: Bool) async {
        guard !acceptsCancellation || !Task.isCancelled else { return }
        let work = reads.begin(includingCollections: includingCollections)
        defer { reads.end(work) }
        do {
            let pages = try await reader.libraries(work.requests)
            if acceptsCancellation { try Task.checkCancellation() }
            if try reads.accept(pages, from: work) { evaluatedAt = now() }
        } catch {
            let interrupted = Task.isCancelled || error is CancellationError
            reads.complete(interrupted ? .cancelled : .failed(error), from: work)
        }
    }

    func cancelOpening(id: UUID) {
        guard openingRequest == id else { return }
        openingRequest = nil
    }

    func open(_ source: EditorSource = .new, requestID: UUID = UUID()) async {
        guard editor == nil, openingRequest == nil, !Task.isCancelled else { return }
        openingRequest = requestID
        operationFailure = nil
        defer {
            if openingRequest == requestID { openingRequest = nil }
        }
        do {
            let input = try await obtainDraft(source)
            guard !Task.isCancelled, openingRequest == requestID else {
                await releaseUnpresented(input, source: source)
                return
            }
            setNoticePresentation(false)
            editor = input
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, openingRequest == requestID else { return }
            recordFailure(.open, error)
        }
    }

    private func releaseUnpresented(_ input: Draft, source: EditorSource) async {
        switch source {
        case .new: try? await store.keepDraft(input)
        case .snippet, .draft: break
        }
    }

    private func obtainDraft(_ source: EditorSource) async throws -> Draft {
        switch source {
        case .draft(let id): try await opener.draft(id)
        case .snippet(let id): try await opener.editingDraft(for: id)
        case .new: try await opener.beginDraft(target: .new, body: "")
        }
    }

    func copy(_ id: UUID, context: NoticeContext? = nil) async {
        guard !Task.isCancelled else { return }
        operationFailure = nil
        let visit = context ?? noticeContext
        do {
            let text = try await store.savedBody(id)
            try Task.checkCancellation()
            let template = SnippetVariables(text)
            guard template.names.isEmpty else {
                variableCopy = VariableCopy(snippetID: id, title: items.first { $0.id == id }?.title ?? "",
                    template: template, context: visit,
                    availability: FeatureAccess.availability(.variableReplacement, pro: proIsActive()))
                return
            }
            await publishCopy(text, itemID: id, visit: visit)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            recordFailure(.copy, error)
        }
    }

    func cancelVariableCopy() { variableCopy = nil }

    func completeVariableCopy(id: UUID, values: [VariableName: String]) async {
        guard !Task.isCancelled, let pending = variableCopy, pending.id == id,
              pending.availability.isAvailable,
              FeatureAccess.availability(.variableReplacement, pro: proIsActive()).isAvailable,
              let text = pending.template.filled(with: values) else { return }
        variableCopy = nil
        do {
            let current = try await store.savedBody(pending.snippetID)
            try Task.checkCancellation()
            guard SnippetText.hasSameBytes(current, pending.template.body) else { throw StoreError.conflict }
            await publishCopy(text, itemID: pending.snippetID, visit: pending.context)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            recordFailure(.copy, error)
        }
    }

    private func publishCopy(_ text: String, itemID: UUID, visit: NoticeContext) async {
        effects.copy(text)
        let record = SnippetUse(id: UUID(), snippetID: itemID, completedAt: now())
        copies[record.id] = CopyRecord(use: record)
        publish(.copied, visit: visit)
        await recordCopy(record.id)
        await fetch(includingCollections: true, acceptsCancellation: false)
    }

    func retryUsageRecording() async {
        guard !Task.isCancelled else { return }
        let ids = Array(copies.keys)
        for id in ids { await recordCopy(id) }
        await fetch(includingCollections: true, acceptsCancellation: false)
    }

    private func recordCopy(_ id: UUID) async {
        guard var record = copies[id] else { return }
        if case .saving = record.status { return }
        record.status = .saving
        copies[id] = record
        do {
            try await recorder.recordUse(record.use)
            copies.removeValue(forKey: id)
            mutationRevision += 1
        } catch {
            let reason = storeError(error)
            guard reason != .missing else {
                copies.removeValue(forKey: id)
                operationFailure = Failure(operation: .recordUse, reason: reason, recovery: .dismiss)
                return
            }
            copies[id]?.status = .failed(reason)
        }
    }

    func pin(_ item: SnippetSummary) async {
        let key = MutationKey(kind: .pin, id: item.id)
        guard !Task.isCancelled, inFlightMutations.insert(key).inserted else { return }
        defer { inFlightMutations.remove(key) }
        operationFailure = nil
        do {
            try await store.setPinned(!item.pinned, id: item.id)
            mutationRevision += 1
            await fetch(includingCollections: true, acceptsCancellation: false)
        } catch { recordFailure(.pin, error) }
    }

    func delete(_ id: UUID, context: NoticeContext? = nil) async {
        await change(.delete, id: id, context: context)
    }

    func restore(_ id: UUID, context: NoticeContext? = nil) async {
        await change(.restore, id: id, context: context)
    }

    func permanentlyDelete(_ id: UUID, context: NoticeContext? = nil) async {
        await change(.permanentlyDelete, id: id, context: context)
    }

    private func change(_ kind: MutationKey.Kind, id: UUID, context: NoticeContext?) async {
        let key = MutationKey(kind: kind, id: id)
        guard !Task.isCancelled, inFlightMutations.insert(key).inserted else { return }
        if kind == .restore { restoringIDs.insert(id) }
        defer {
            inFlightMutations.remove(key)
            if kind == .restore { restoringIDs.remove(id) }
        }
        operationFailure = nil
        let visit = context ?? noticeContext
        let mutation: SnippetMutation
        let operation: Failure.Operation
        switch kind {
        case .delete: mutation = .delete; operation = .delete
        case .restore: mutation = .restore; operation = .restore
        case .permanentlyDelete: mutation = .permanentlyDelete; operation = .permanentlyDelete
        case .pin: return
        }
        do {
            let item = try await store.mutate(mutation, id: id)
            mutationRevision += 1
            switch kind {
            case .delete: publish(.deleted(item), visit: visit)
            case .restore: publish(.restored(item), visit: visit)
            case .permanentlyDelete: publish(.permanentlyDeleted(item), visit: visit)
            case .pin: break
            }
            await fetch(includingCollections: true, acceptsCancellation: false)
        } catch {
            let reason = storeError(error)
            let recovery: Failure.Recovery = kind == .restore && reason != .missing ? .retryRestore(id)
                : reason == .missing ? .reload : .dismiss
            operationFailure = Failure(operation: operation, reason: reason, recovery: recovery)
        }
    }

    func undoNotice(_ id: UUID, context: NoticeContext? = nil) async {
        guard let shown = notice, shown.id == id, let target = shown.undoID else { return }
        await restore(target, context: context)
        if operationFailure != nil, notice?.id == id { clearNotice() }
    }

    func setNoticePresentation(_ isPresented: Bool) {
        guard noticeContext.isPresented != isPresented else { return }
        noticeContext = NoticeContext(isPresented: isPresented)
        clearNotice()
    }

    func clearNotice() {
        notice = nil
        noticeDeadline = nil
    }

    func expireNotice(id: UUID) async {
        guard let shown = notice, shown.id == id else { return }
        let deadline = noticeDeadline ?? ContinuousClock.now.advanced(by: shown.duration)
        noticeDeadline = deadline
        do {
            try await noticeSleep(deadline)
            try Task.checkCancellation()
            if notice?.id == id { clearNotice() }
        } catch {
            guard notice?.id == id, !(error is CancellationError), !Task.isCancelled else { return }
            recordFailure(.notice, error)
        }
    }

    private func publish(_ result: Notice.Result, visit: NoticeContext) {
        guard visit.isPresented, visit == noticeContext else { return }
        let message = Notice(origin: surface.noticeOrigin, result: result)
        notice = message
        noticeDeadline = nil
        feedback += 1
        effects.announce(message)
    }

    private func recordFailure(_ operation: Failure.Operation, _ error: any Error) {
        let reason = storeError(error)
        operationFailure = Failure(operation: operation, reason: reason, recovery: reason == .missing ? .reload : .dismiss)
    }

    private func storeError(_ error: any Error) -> StoreError { error as? StoreError ?? .database }
}
