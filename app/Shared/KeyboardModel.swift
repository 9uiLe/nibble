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
    private let reader: any KeyboardReading
    private weak var effects: (any KeyboardEffects)?
    private(set) var request = KeyboardRequest()
    private(set) var loadID = UUID()
    private(set) var isActive = false
    private(set) var loading = true
    private(set) var failure: String?
    private(set) var message: String?
    private(set) var hasFullAccess = false
    private(set) var needsSwitchKey = false
    private var operation: UUID?
    private var snapshot: (request: KeyboardRequest, page: KeyboardPage)?

    var page: KeyboardPage? { snapshot?.page }
    var isCurrent: Bool { snapshot?.request == request && !loading && failure == nil }
    var isUsing: Bool { operation != nil }

    init(reader: any KeyboardReading, effects: any KeyboardEffects) {
        self.reader = reader
        self.effects = effects
    }

    func activate() {
        isActive = true
        request = KeyboardRequest(filter: request.filter)
        requestReload()
    }

    func deactivate() {
        isActive = false
        loadID = UUID()
        operation = nil
        snapshot = nil
        failure = nil
        message = nil
        loading = true
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
        loading = true
        failure = nil
        message = nil
        operation = nil
    }

    func refresh() async {
        guard isActive, !Task.isCancelled else { return }
        let id = loadID
        let requested = request
        do {
            let page = try await reader.page(requested)
            try Task.checkCancellation()
            guard isActive, loadID == id else { return }
            snapshot = (requested, page)
            loading = false
        } catch {
            guard isActive, loadID == id else { return }
            loading = false
            failure = Task.isCancelled || error is CancellationError
                ? "読み込みを中断しました。更新して再試行できます。" : error.localizedDescription
        }
    }

    func use(_ item: SnippetSummary, as use: Use) async {
        guard isActive, isCurrent, operation == nil, !Task.isCancelled, let effects else { return }
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
