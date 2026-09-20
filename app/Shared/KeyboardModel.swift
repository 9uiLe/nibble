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
    struct Detail: Equatable {
        let id: UUID
        var item: SnippetSummary
        var body: String?
        var failure: String?
    }
    struct Notice: Equatable {
        let id = UUID()
        let message: String
        let insertedID: UUID?
        let expires: Bool
    }
    private enum LoadState: Equatable {
        case inactive, pending, loading(UUID), ready, failed(String)
    }
    private let reader: any KeyboardReading
    private weak var effects: (any KeyboardEffects)?
    private(set) var request = KeyboardRequest()
    private(set) var loadID = UUID()
    private var loadState = LoadState.inactive
    private(set) var notice: Notice?
    private(set) var detail: Detail?
    var message: String? { notice?.message }
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
        notice = nil
        detail = nil
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
        detail = nil
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
                ? "読み込みを中断しました。更新ボタンを押してください。" : "一覧を読み込めませんでした。" + recoveryMessage(error))
        }
    }

    func use(_ item: SnippetSummary, as use: Use) async {
        guard isActive, isCurrent, operation == nil, !Task.isCancelled, let effects else { return }
        guard contains(item) else { return }
        if case .copy = use, !effects.canCopy {
            notify(fullAccessMessage(for: "コピー"))
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
            guard isActive, loadID == generation, operation == id else { return }
            switch use {
            case .insert:
                guard effects.destination == destination else {
                    notify("入力位置が変わったため、本文を送っていません。入力先を確認して、項目をもう一度選んでください。")
                    return
                }
                effects.insert(text)
                closeDetail()
                notify("本文を送りました", insertedID: item.id, expires: true)
            case .copy:
                guard effects.canCopy else {
                    notify(fullAccessMessage(for: "コピー"))
                    return
                }
                effects.copy(text)
                notify("コピーしました", expires: true)
            }
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, operation == id, !Task.isCancelled else { return }
            let result = use == .copy ? "コピーできませんでした。" : "本文を送れませんでした。"
            notify(result + recoveryMessage(error))
        }
    }

    func openDetail(_ item: SnippetSummary) {
        guard isCurrent, !isUsing, contains(item) else { return }
        notice = nil
        detail = Detail(id: UUID(), item: item)
    }

    func closeDetail() { detail = nil }

    func loadDetail() async {
        guard let selected = detail, selected.body == nil else { return }
        let generation = loadID
        do {
            let body = try await reader.body(for: selected.item)
            try Task.checkCancellation()
            guard isActive, loadID == generation, detail?.id == selected.id else { return }
            detail?.body = body
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, detail?.id == selected.id else { return }
            let message = "本文を読み込めませんでした。" + recoveryMessage(error)
            detail?.failure = message
        }
    }

    func togglePin() async {
        guard isActive, isCurrent, !isUsing, !Task.isCancelled,
              let selected = detail, selected.body != nil, let effects else { return }
        guard effects.canCopy else {
            notify(fullAccessMessage(for: "ピン留めの変更"))
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
            if detail?.id == selected.id { detail?.item = updated }
            if let snapshot {
                let items = snapshot.page.items.compactMap { item -> SnippetSummary? in
                    guard item.id == updated.id else { return item }
                    return request.filter == .pinned && !updated.pinned ? nil : updated
                }
                self.snapshot = (snapshot.request, KeyboardPage(items: items, hasMore: snapshot.page.hasMore))
            }
            notify(updated.pinned ? "ピン留めしました" : "ピン留めを解除しました", expires: true)
            // Reconcile ordering and page boundaries without resetting the selected filter.
            let refreshed = try await reader.page(request)
            guard isActive, loadID == generation, operation == id else { return }
            snapshot = (request, refreshed)
        } catch is CancellationError { }
        catch {
            guard isActive, loadID == generation, operation == id else { return }
            let result = pinWasChanged ? "ピン留めは変更しましたが、一覧を更新できませんでした。" : "ピン留めを変更できませんでした。"
            notify(result + recoveryMessage(error))
        }
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

    private func notify(_ message: String, insertedID: UUID? = nil, expires: Bool = false) {
        notice = Notice(message: message, insertedID: insertedID, expires: expires)
    }

    private func fullAccessMessage(for operation: String) -> String {
        "\(operation)にはフルアクセスが必要です。nibbleの「設定」→「nibbleキーボード」で設定方法を確認してください。"
    }

    private func recoveryMessage(_ error: Error) -> String {
        if error as? StoreError == .newerVersion {
            return "nibbleを最新バージョンに更新してください。"
        }
        if case KeyboardReadError.notPrepared = error { return error.localizedDescription }
        let reason = (error as? StoreError)?.localizedDescription
            ?? (error is KeyboardReadError ? "項目が変更されています。" : "保存データを読み込めませんでした。")
        let next = detail == nil ? "更新ボタンを押してください。" : "「一覧に戻る」を押してから、更新ボタンを押してください。"
        return reason + next
    }

    func dismiss() { effects?.dismiss() }
}
