import Foundation
import Observation

struct KeyboardDestination: Equatable {
    let document: UUID
    let revision: UUID
}

@MainActor
protocol KeyboardEffects: AnyObject {
    var destination: KeyboardDestination { get }
    var canCopy: Bool { get }
    func insert(_ text: String)
    func copy(_ text: String)
    func dismiss()
}

@MainActor @Observable
final class KeyboardModel {
    enum Use: Equatable { case insert, copy }
    struct VariableUse: Identifiable {
        let id = UUID()
        let item: SnippetSummary
        let mode: Use
        let template: SnippetVariables
        let destination: KeyboardDestination
        let generation: UUID
        let availability: FeatureAvailability
    }
    enum Action: Equatable { case load, insert, copy, preview, pin, reloadAfterPin, changed }
    enum Reason: Equatable {
        case store(StoreError), notPrepared, changed, unavailable
        init(_ error: Error) {
            if let error = error as? StoreError { self = .store(error) }
            else if let error = error as? KeyboardReadError { self = error == .notPrepared ? .notPrepared : .changed }
            else { self = .unavailable }
        }
    }
    enum Message: Equatable {
        case cancelled, requiresFullAccess(Action), inputChanged, inserted(UUID), copied, pinChanged(Bool)
        case failed(Action, Reason, detailIsOpen: Bool)
    }
    struct Detail: Equatable {
        let id: UUID
        let item: SnippetSummary
        let body: String?
        let error: Message?
    }
    private struct Selection {
        let id = UUID()
        let itemID: UUID
        var body: String?
        var error: Message?
    }
    struct Notice: Equatable {
        let id = UUID()
        let result: Message
        var insertedID: UUID? {
            if case .inserted(let id) = result { return id }
            return nil
        }
        var expires: Bool {
            switch result {
            case .inserted, .copied, .pinChanged: true
            default: false
            }
        }
    }
    private enum LoadState: Equatable {
        case inactive, pending, loading(UUID), ready, failed(Message)
    }
    private let reader: any KeyboardReading
    private weak var effects: (any KeyboardEffects)?
    private(set) var request = KeyboardRequest()
    private(set) var loadID = UUID()
    private var loadState = LoadState.inactive
    private(set) var notice: Notice?
    private(set) var variableUse: VariableUse?
    private var selection: Selection?
    private var rows: [UUID: SnippetSummary] = [:]
    var detail: Detail? {
        guard let selection, let item = rows[selection.itemID] else { return nil }
        return Detail(id: selection.id, item: item, body: selection.body, error: selection.error)
    }
    private(set) var hasFullAccess = false
    private(set) var needsSwitchKey = false
    private var operation: UUID?
    private var snapshot: (request: KeyboardRequest, ids: [UUID], hasMore: Bool)?

    var isActive: Bool { loadState != .inactive }
    var loading: Bool {
        switch loadState {
        case .inactive, .pending, .loading: true
        case .ready, .failed: false
        }
    }
    var loadFailure: Message? {
        if case .failed(let message) = loadState { return message }
        return nil
    }
    var page: KeyboardPage? {
        snapshot.map { snapshot in
            KeyboardPage(items: snapshot.ids.compactMap { rows[$0] }, hasMore: snapshot.hasMore)
        }
    }
    var isCurrent: Bool { snapshot?.request == request && loadState == .ready }
    var isUsing: Bool { operation != nil }

    init(reader: any KeyboardReading, effects: any KeyboardEffects) {
        self.reader = reader
        self.effects = effects
    }

    func activate() {
        loadState = .pending
        requestReload()
    }

    func deactivate() {
        loadState = .inactive
        loadID = UUID()
        operation = nil
        snapshot = nil
        notice = nil
        variableUse = nil
        selection = nil
        rows = [:]
    }

    func updateCapabilities(fullAccess: Bool, needsSwitchKey: Bool) {
        hasFullAccess = fullAccess
        self.needsSwitchKey = needsSwitchKey
    }

    func select(_ filter: KeyboardFilter) {
        guard filter != request.filter else { return }
        request = KeyboardRequest(filter: filter)
        invalidate()
    }

    func movePage(forward: Bool) {
        guard isCurrent, forward ? page?.hasMore == true : request.offset > 0 else { return }
        request = KeyboardRequest(filter: request.filter,
            offset: request.offset + (forward ? KeyboardRequest.pageSize : -KeyboardRequest.pageSize))
        invalidate()
    }

    func requestReload() {
        request = KeyboardRequest(filter: request.filter)
        invalidate()
    }

    private func invalidate() {
        loadID = UUID()
        if isActive { loadState = .pending }
        notice = nil
        variableUse = nil
        selection = nil
        operation = nil
    }

    func refresh() async {
        guard isActive, !Task.isCancelled else { return }
        let id = loadID
        let requested = request
        let readID = UUID()
        loadState = .loading(readID)
        do {
            let page = try await reader.page(requested)
            try Task.checkCancellation()
            guard loadID == id, loadState == .loading(readID) else { return }
            replacePage(page, for: requested)
            loadState = .ready
        } catch {
            guard loadID == id, loadState == .loading(readID) else { return }
            loadState = .failed(Task.isCancelled || error is CancellationError
                ? .cancelled : failure(for: .load, error: error))
        }
    }

    func use(_ item: SnippetSummary, as use: Use) async {
        guard isActive, isCurrent, operation == nil, !Task.isCancelled, let effects else { return }
        guard contains(item) else { return }
        if case .copy = use, !effects.canCopy {
            notify(.requiresFullAccess(.copy))
            return
        }
        let id = UUID()
        let generation = loadID
        let destination = effects.destination
        operation = id
        notice = nil
        defer { if operation == id { operation = nil } }
        do {
            let text = try await reader.body(for: item)
            try Task.checkCancellation()
            guard isActive, loadID == generation, operation == id, contains(item) else { return }
            let template = SnippetVariables(text)
            if !template.names.isEmpty {
                variableUse = VariableUse(item: item, mode: use, template: template,
                    destination: destination, generation: generation,
                    availability: FeatureAccess.availability(.variableReplacement, pro: ProAccess.isActive()))
                return
            }
            switch use {
            case .insert:
                guard effects.destination == destination else {
                    notify(.inputChanged)
                    return
                }
                effects.insert(text)
                closeDetail()
                notify(.inserted(item.id))
            case .copy:
                guard effects.canCopy else {
                    notify(.requiresFullAccess(.copy))
                    return
                }
                effects.copy(text)
                notify(.copied)
            }
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, operation == id, !Task.isCancelled else { return }
            notify(failure(for: use == .copy ? .copy : .insert, error: error))
        }
    }

    func cancelVariableUse() { variableUse = nil }

    func completeVariableUse(values: [String: String]) async {
        guard let pending = variableUse, pending.availability.isAvailable,
              let text = pending.template.filled(with: values), isActive, isCurrent,
              loadID == pending.generation, contains(pending.item), operation == nil,
              let effects else { return }
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil } }
        do {
            let current = try await reader.body(for: pending.item)
            try Task.checkCancellation()
            guard isActive, isCurrent, loadID == pending.generation, operation == id,
                  variableUse?.id == pending.id, contains(pending.item) else { return }
            variableUse = nil
            guard current.utf8.elementsEqual(pending.template.body.utf8) else {
                notify(failure(for: .changed, error: KeyboardReadError.changed))
                return
            }
            switch pending.mode {
            case .insert:
                guard effects.destination == pending.destination else { notify(.inputChanged); return }
                effects.insert(text)
                closeDetail()
                notify(.inserted(pending.item.id))
            case .copy:
                guard effects.canCopy else { notify(.requiresFullAccess(.copy)); return }
                effects.copy(text)
                notify(.copied)
            }
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == pending.generation, operation == id else { return }
            variableUse = nil
            notify(failure(for: pending.mode == .copy ? .copy : .insert, error: error))
        }
    }

    func openDetail(_ item: SnippetSummary) {
        guard isCurrent, !isUsing, contains(item) else { return }
        notice = nil
        selection = Selection(itemID: item.id)
    }

    func closeDetail() { selection = nil }

    func loadDetail() async {
        guard let selected = detail, selected.body == nil else { return }
        let generation = loadID
        do {
            let body = try await reader.body(for: selected.item)
            try Task.checkCancellation()
            guard isActive, loadID == generation, detail?.id == selected.id,
                  detail?.item.revision == selected.item.revision else { return }
            selection?.body = body
            selection?.error = nil
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, detail?.id == selected.id,
                  detail?.item.revision == selected.item.revision else { return }
            let message = failure(for: .preview, error: error)
            selection?.error = message
        }
    }

    func togglePin() async {
        guard isActive, isCurrent, !isUsing, !Task.isCancelled,
              let selected = detail, selected.body != nil, let effects else { return }
        guard effects.canCopy else {
            notify(.requiresFullAccess(.pin))
            return
        }
        let id = UUID()
        let generation = loadID
        operation = id
        notice = nil
        var pinWasChanged = false
        defer { if operation == id { operation = nil } }
        do {
            let updated = try await reader.setPinned(!selected.item.pinned, for: selected.item)
            pinWasChanged = true
            // A committed write remains a success even if cancellation arrives after commit.
            guard isActive, loadID == generation, operation == id else { return }
            rows[updated.id] = updated
            if request.filter == .pinned && !updated.pinned { snapshot?.ids.removeAll { $0 == updated.id } }
            notify(.pinChanged(updated.pinned))
            // Reconcile ordering and page boundaries without resetting the selected filter.
            let refreshed = try await reader.page(request)
            guard isActive, loadID == generation, operation == id else { return }
            replacePage(refreshed, for: request)
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, operation == id else { return }
            notify(failure(for: pinWasChanged ? .reloadAfterPin : .pin, error: error))
        }
    }

    /// One value per item feeds both the list and the selected detail. A selected
    /// item can remain outside the pinned page after unpinning, until detail closes.
    private func replacePage(_ page: KeyboardPage, for request: KeyboardRequest) {
        let selectedItem = selection.flatMap { rows[$0.itemID] }
        rows = Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        if let selectedItem {
            if let current = rows[selectedItem.id] {
                if current.revision != selectedItem.revision {
                    let message = failure(for: .changed, error: KeyboardReadError.changed)
                    selection?.body = nil
                    selection?.error = message
                }
            } else { rows[selectedItem.id] = selectedItem }
        }
        snapshot = (request, page.items.map(\.id), page.hasMore)
    }

    func expireNotice(id: UUID) async {
        guard notice?.id == id, notice?.expires == true else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        guard !Task.isCancelled, notice?.id == id else { return }
        notice = nil
    }

    private func contains(_ item: SnippetSummary) -> Bool {
        page?.items.contains(where: { $0.id == item.id && $0.revision == item.revision }) == true
            || (detail?.item == item && detail?.body != nil)
    }

    private func notify(_ result: Message) {
        notice = Notice(result: result)
    }

    private func failure(for action: Action, error: Error) -> Message {
        .failed(action, Reason(error), detailIsOpen: selection != nil)
    }

    func dismiss() { effects?.dismiss() }
}
