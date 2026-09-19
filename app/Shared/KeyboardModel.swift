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
    enum Use { case insert, copy }
    private enum LoadState: Equatable {
        case inactive, pending, loading(UUID), ready, failed(String)
    }
    private let reader: any KeyboardReading
    private weak var effects: (any KeyboardEffects)?
    private(set) var request = KeyboardRequest()
    private(set) var loadID = UUID()
    private var loadState = LoadState.inactive
    private(set) var message: String?
    private(set) var hasFullAccess = false
    private(set) var needsSwitchKey = false
    private var operation: UUID?
    private var snapshot: (request: KeyboardRequest, page: KeyboardPage)?

    var isActive: Bool { loadState != .inactive }
    var loading: Bool {
        switch loadState {
        case .inactive, .pending, .loading: true
        case .ready, .failed: false
        }
    }
    var failure: String? {
        if case .failed(let message) = loadState { return message }
        return nil
    }
    var page: KeyboardPage? { snapshot?.page }
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
        message = nil
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
        message = nil
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
            snapshot = (requested, page)
            loadState = .ready
        } catch {
            guard loadID == id, loadState == .loading(readID) else { return }
            loadState = .failed(Task.isCancelled || error is CancellationError
                ? "読み込みを中断しました。更新して再試行できます。" : error.localizedDescription)
        }
    }

    func use(_ item: SnippetSummary, as use: Use) async {
        guard isActive, isCurrent, operation == nil, !Task.isCancelled, let effects else { return }
        guard page?.items.contains(where: { $0.id == item.id && $0.revision == item.revision }) == true else { return }
        if case .copy = use, !effects.canCopy {
            message = "コピーには、iOS設定でnibbleのフルアクセスを許可してください。"
            return
        }
        let id = UUID()
        let generation = loadID
        let destination = effects.destination
        operation = id
        message = nil
        defer { if operation == id { operation = nil } }
        do {
            let text = try await reader.body(for: item)
            try Task.checkCancellation()
            guard isActive, loadID == generation, operation == id else { return }
            switch use {
            case .insert:
                guard effects.destination == destination else {
                    message = "入力位置が変わりました。もう一度項目を選んでください。"
                    return
                }
                effects.insert(text)
                message = "入力先へ本文を渡しました"
            case .copy:
                guard effects.canCopy else {
                    message = "フルアクセスが無効になりました。コピーしていません。"
                    return
                }
                effects.copy(text)
                message = "コピーしました"
            }
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, operation == id, !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }

    func dismiss() { effects?.dismiss() }
}
