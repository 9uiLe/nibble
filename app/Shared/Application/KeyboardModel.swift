import Foundation
import Observation

struct KeyboardDestination: Equatable {
    let document: UUID?
    let revision: UUID
}

@MainActor
protocol KeyboardEffects: AnyObject {
    var destination: KeyboardDestination { get }
    var canCopy: Bool { get }
    func copy(_ text: String)
    func insert(_ text: String, into destination: KeyboardDestination) -> Bool
    func dismiss()
    func holdInputDocument(_ destination: KeyboardDestination) -> Bool
    func releaseInputDocument()
}

@MainActor @Observable
final class KeyboardModel {
    enum Use: Equatable { case insert, copy }
    enum Action: Equatable { case load, insert, copy, preview, pin, reloadAfterPin, changed }

    enum Reason: Equatable {
        case store(StoreError), notPrepared, changed, unavailable
        init(_ error: any Error) {
            switch error {
            case let value as StoreError: self = .store(value)
            case KeyboardReadError.notPrepared: self = .notPrepared
            case KeyboardReadError.changed: self = .changed
            default: self = .unavailable
            }
        }
    }

    enum Message: Equatable {
        case cancelled
        case requiresFullAccess(Action)
        case inputChanged
        case inserted(UUID)
        case copied
        case pinChanged(Bool)
        case failed(Action, Reason, detailIsOpen: Bool)
    }

    struct Notice: Equatable {
        let id = UUID()
        let result: Message
        var insertedID: UUID? {
            guard case .inserted(let id) = result else { return nil }
            return id
        }
        var expires: Bool {
            switch result {
            case .inserted, .copied, .pinChanged: true
            default: false
            }
        }
    }

    struct Detail: Equatable {
        enum Content: Equatable { case loading, ready(String), failed(Message) }
        let id: UUID
        let item: SnippetSummary
        let content: Content
        var body: String? {
            guard case .ready(let text) = content else { return nil }
            return text
        }
        var error: Message? {
            guard case .failed(let message) = content else { return nil }
            return message
        }
    }

    struct VariableUse: Identifiable {
        let id = UUID()
        let item: SnippetSummary
        let mode: Use
        let template: SnippetVariables
        let destination: KeyboardDestination
        let generation: UUID
        let availability: FeatureAvailability
    }

    private enum Phase: Equatable { case hidden, pending, reading(UUID), ready, failed(Message) }
    private struct Selected {
        let id = UUID()
        let itemID: UUID
        var content: Detail.Content = .loading
    }
    private struct PageSnapshot {
        let request: KeyboardRequest
        var ids: [UUID]
        let hasMore: Bool
    }
    private struct Operation {
        let id = UUID()
        let generation: UUID
    }

    private let reader: any KeyboardReading
    private weak var effects: (any KeyboardEffects)?
    private let proIsActive: () -> Bool
    private var phase: Phase = .hidden
    private var summaries: [UUID: SnippetSummary] = [:]
    private var snapshot: PageSnapshot?
    private var selected: Selected?
    private var previewRead: UUID?
    private var activeOperation: Operation?
    private(set) var request = KeyboardRequest()
    private(set) var loadID = UUID()
    private(set) var hasFullAccess = false
    private(set) var needsSwitchKey = false
    private(set) var notice: Notice?
    private(set) var variableUse: VariableUse?

    init(reader: any KeyboardReading, effects: any KeyboardEffects, proIsActive: @escaping () -> Bool = { false }) {
        self.reader = reader
        self.effects = effects
        self.proIsActive = proIsActive
    }

    var isActive: Bool { phase != .hidden }
    var loading: Bool {
        switch phase {
        case .hidden, .pending, .reading: true
        case .ready, .failed: false
        }
    }
    var isCurrent: Bool { phase == .ready && snapshot?.request == request }
    var isUsing: Bool { activeOperation != nil }
    var loadFailure: Message? {
        guard case .failed(let failure) = phase else { return nil }
        return failure
    }
    var page: KeyboardPage? {
        guard let snapshot else { return nil }
        return KeyboardPage(items: snapshot.ids.compactMap { summaries[$0] }, hasMore: snapshot.hasMore)
    }
    var detail: Detail? {
        guard let selected, let item = summaries[selected.itemID] else { return nil }
        return Detail(id: selected.id, item: item, content: selected.content)
    }

    func activate() {
        request = KeyboardRequest()
        phase = .pending
        invalidateRequest()
    }

    func deactivate() {
        phase = .hidden
        invalidateRequest()
        summaries.removeAll()
        snapshot = nil
    }

    func updateCapabilities(fullAccess: Bool, needsSwitchKey: Bool) {
        hasFullAccess = fullAccess
        self.needsSwitchKey = needsSwitchKey
    }

    func select(_ filter: KeyboardFilter) {
        guard filter != request.filter else { return }
        request = KeyboardRequest(filter: filter)
        invalidateRequest()
    }

    func movePage(forward: Bool) {
        guard isCurrent else { return }
        guard forward ? snapshot?.hasMore == true : request.offset > 0 else { return }
        let distance = forward ? KeyboardRequest.pageSize : -KeyboardRequest.pageSize
        request = KeyboardRequest(filter: request.filter, offset: request.offset + distance)
        invalidateRequest()
    }

    func requestReload() {
        request = KeyboardRequest(filter: request.filter)
        invalidateRequest()
    }

    private func invalidateRequest() {
        loadID = UUID()
        previewRead = nil
        selected = nil
        activeOperation = nil
        notice = nil
        cancelVariableUse()
        if isActive { phase = .pending }
    }

    func refresh() async {
        guard isActive, !Task.isCancelled else { return }
        let generation = loadID
        let read = UUID()
        let requested = request
        phase = .reading(read)
        do {
            let result = try await reader.page(requested)
            try Task.checkCancellation()
            guard loadID == generation, phase == .reading(read) else { return }
            applyPage(result, request: requested)
            phase = .ready
        } catch {
            guard loadID == generation, phase == .reading(read) else { return }
            let message: Message = Task.isCancelled || error is CancellationError ? .cancelled : failed(.load, error)
            phase = .failed(message)
        }
    }

    func use(_ item: SnippetSummary, as mode: Use) async {
        guard !Task.isCancelled, isCurrent, activeOperation == nil, owns(item), let effects else { return }
        guard mode != .copy || effects.canCopy else { inform(.requiresFullAccess(.copy)); return }
        let work = Operation(generation: loadID)
        let destination = effects.destination
        guard mode != .insert || destination.document != nil else { inform(.inputChanged); return }
        activeOperation = work
        notice = nil
        defer { finishOperation(work) }
        do {
            let text = try await reader.body(for: item)
            try Task.checkCancellation()
            guard admits(work), owns(item) else { return }
            guard mode != .insert || effects.destination == destination else { inform(.inputChanged); return }
            let template = SnippetVariables(text)
            if template.names.isEmpty {
                deliver(text, itemID: item.id, mode: mode, expectedDocument: destination)
                return
            }
            if mode == .insert, !effects.holdInputDocument(destination) {
                effects.releaseInputDocument()
                inform(.inputChanged)
                return
            }
            guard admits(work), owns(item) else {
                effects.releaseInputDocument()
                return
            }
            variableUse = VariableUse(item: item, mode: mode, template: template,
                destination: destination, generation: loadID,
                availability: FeatureAccess.availability(.variableReplacement, pro: proIsActive()))
        } catch {
            guard admits(work), !Task.isCancelled, !(error is CancellationError) else { return }
            inform(failed(mode == .copy ? .copy : .insert, error))
        }
    }

    func cancelVariableUse() {
        variableUse = nil
        effects?.releaseInputDocument()
    }

    func completeVariableUse(values: [VariableName: String]) async {
        guard !Task.isCancelled, isCurrent, activeOperation == nil, let pending = variableUse,
              pending.generation == loadID, owns(pending.item), pending.availability.isAvailable,
              FeatureAccess.availability(.variableReplacement, pro: proIsActive()).isAvailable,
              let text = pending.template.filled(with: values) else { return }
        let work = Operation(generation: loadID)
        activeOperation = work
        defer {
            finishOperation(work)
            if variableUse == nil { effects?.releaseInputDocument() }
        }
        do {
            let stored = try await reader.body(for: pending.item)
            try Task.checkCancellation()
            guard admits(work), variableUse?.id == pending.id, owns(pending.item) else { return }
            defer {
                if variableUse?.id == pending.id { variableUse = nil }
            }
            guard SnippetText.hasSameBytes(stored, pending.template.body) else {
                inform(failed(.changed, KeyboardReadError.changed))
                return
            }
            deliver(text, itemID: pending.item.id, mode: pending.mode, expectedDocument: pending.destination)
        } catch {
            guard admits(work), !Task.isCancelled, !(error is CancellationError) else { return }
            cancelVariableUse()
            inform(failed(pending.mode == .copy ? .copy : .insert, error))
        }
    }

    private func deliver(_ text: String, itemID: UUID, mode: Use, expectedDocument: KeyboardDestination) {
        guard let effects else { return }
        switch mode {
        case .copy:
            guard effects.canCopy else { inform(.requiresFullAccess(.copy)); return }
            effects.copy(text)
            inform(.copied)
        case .insert:
            let current = effects.destination
            guard expectedDocument.document != nil, current == expectedDocument,
                  effects.insert(text, into: expectedDocument) else { inform(.inputChanged); return }
            closeDetail()
            inform(.inserted(itemID))
        }
    }

    func openDetail(_ item: SnippetSummary) {
        guard isCurrent, !isUsing, owns(item) else { return }
        notice = nil
        selected = Selected(itemID: item.id)
        previewRead = nil
    }

    func closeDetail() {
        selected = nil
        previewRead = nil
    }

    func loadDetail() async {
        guard !Task.isCancelled, let opened = detail, opened.body == nil else { return }
        let generation = loadID
        let read = UUID()
        previewRead = read
        do {
            let body = try await reader.body(for: opened.item)
            try Task.checkCancellation()
            guard admitsPreview(read, generation: generation, detail: opened) else { return }
            selected?.content = .ready(body)
        } catch {
            guard !(error is CancellationError), !Task.isCancelled,
                  admitsPreview(read, generation: generation, detail: opened) else { return }
            let message = failed(.preview, error)
            selected?.content = .failed(message)
        }
    }

    private func admitsPreview(_ read: UUID, generation: UUID, detail opened: Detail) -> Bool {
        isActive && generation == loadID && previewRead == read
            && detail?.id == opened.id && detail?.item.revision == opened.item.revision
    }

    func togglePin() async {
        guard !Task.isCancelled, isCurrent, !isUsing, let opened = detail,
              opened.body != nil, let effects else { return }
        guard effects.canCopy else { inform(.requiresFullAccess(.pin)); return }
        let work = Operation(generation: loadID)
        activeOperation = work
        notice = nil
        var committed = false
        defer { finishOperation(work) }
        do {
            let updated = try await reader.setPinned(!opened.item.pinned, for: opened.item)
            committed = true
            guard admits(work) else { return }
            summaries[updated.id] = updated
            if request.filter == .pinned, !updated.pinned { snapshot?.ids.removeAll { $0 == updated.id } }
            inform(.pinChanged(updated.pinned))
            let reconciled = try await reader.page(request)
            guard admits(work) else { return }
            applyPage(reconciled, request: request)
        } catch {
            guard admits(work) else { return }
            guard !(error is CancellationError) else { return }
            inform(failed(committed ? .reloadAfterPin : .pin, error))
        }
    }

    private func applyPage(_ page: KeyboardPage, request: KeyboardRequest) {
        let oldSelection = selected.flatMap { summaries[$0.itemID] }
        var next = Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        if let oldSelection {
            switch next[oldSelection.id] {
            case .some(let current):
                if current.revision != oldSelection.revision {
                    previewRead = nil
                    let message = failed(.changed, KeyboardReadError.changed)
                    selected?.content = .failed(message)
                }
            case .none: next[oldSelection.id] = oldSelection
            }
        }
        summaries = next
        snapshot = PageSnapshot(request: request, ids: page.items.map(\.id), hasMore: page.hasMore)
    }

    func expireNotice(id: UUID) async {
        guard notice?.id == id, notice?.expires == true else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        guard !Task.isCancelled, notice?.id == id else { return }
        notice = nil
    }

    func dismiss() { effects?.dismiss() }

    private func owns(_ item: SnippetSummary) -> Bool {
        guard summaries[item.id]?.revision == item.revision else { return false }
        return snapshot?.ids.contains(item.id) == true || (detail?.item.id == item.id && detail?.body != nil)
    }

    private func admits(_ work: Operation) -> Bool {
        isCurrent && work.generation == loadID && activeOperation?.id == work.id
    }

    private func finishOperation(_ work: Operation) {
        if activeOperation?.id == work.id { activeOperation = nil }
    }

    private func inform(_ result: Message) { notice = Notice(result: result) }
    private func failed(_ action: Action, _ error: any Error) -> Message {
        .failed(action, Reason(error), detailIsOpen: selected != nil)
    }
}
