import Foundation
import Observation

@MainActor
protocol PreparedKeyboardDelivery: AnyObject {
    func documentIdentifier() -> UUID?
    func insert(_ text: String, document: UUID, admission: () -> Bool) -> Bool
    func dismiss()
}

@MainActor @Observable
final class PreparedKeyboardModel {
    static let maximumCards = 50

    enum Listing {
        case idle
        case loading
        case cards([PreparedCardSummary])
        case failed(WorkspaceError)
    }

    enum Refusal: Equatable {
        case inputChanged
        case unavailableInput
        case sourceChanged
        case unsupportedContent
        case cancelled
        case departed
        case deliveryRefused
        case storage(WorkspaceError)
    }

    enum PreviewStatus: Equatable {
        case loading
        case ready
        case checking
        case refused(Refusal)
        case sent
    }

    struct SelectionID: Equatable { private let value = UUID() }

    struct Preview: Equatable {
        let operation: SelectionID
        let summary: PreparedCardSummary
        var card: TextCard?
        var status: PreviewStatus
    }

    private struct LoadGeneration: Equatable { private let value = UUID() }
    private struct InputGeneration: Equatable { private let value = UUID() }
    private struct Lease {
        let operation: SelectionID
        let document: UUID
        let generation: InputGeneration
    }

    private let suppliedStorage: (any WorkspaceStorage)?
    @ObservationIgnored private weak var delivery: (any PreparedKeyboardDelivery)?
    private var loadGeneration = LoadGeneration()
    private var inputGeneration = InputGeneration()
    private var lease: Lease?
    private var visible = false
    private(set) var listing: Listing = .idle
    private(set) var preview: Preview?
    private(set) var needsInputModeSwitchKey = false

    init(storage: (any WorkspaceStorage)? = nil, delivery: any PreparedKeyboardDelivery) {
        suppliedStorage = storage
        self.delivery = delivery
    }

    var canInsert: Bool {
        guard visible, let preview, preview.status == .ready, let lease else { return false }
        return lease.operation == preview.operation && lease.generation == inputGeneration
    }

    func activate(needsInputModeSwitchKey: Bool) {
        visible = true
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
    }

    func updateSwitchKey(_ required: Bool) { needsInputModeSwitchKey = required }

    func deactivate() {
        visible = false
        loadGeneration = LoadGeneration()
        revoke(.departed)
    }

    func inputChanged() {
        inputGeneration = InputGeneration()
        revoke(.inputChanged)
    }

    func closePreview() {
        lease = nil
        preview = nil
    }

    func dismiss() {
        deactivate()
        delivery?.dismiss()
    }

    func refresh() async {
        let request = LoadGeneration()
        loadGeneration = request
        listing = .loading
        revoke(.sourceChanged)
        do {
            let storage = try await reader()
            guard request == loadGeneration, visible, !Task.isCancelled else {
                finishCancelledLoad(request)
                return
            }
            let cards = try await storage.keyboardSummaries(limit: Self.maximumCards)
            guard request == loadGeneration, visible, !Task.isCancelled else {
                finishCancelledLoad(request)
                return
            }
            listing = .cards(Array(cards.prefix(Self.maximumCards)))
        } catch {
            guard request == loadGeneration else { return }
            if Task.isCancelled || error is CancellationError {
                listing = .idle
                return
            }
            listing = .failed(WorkspaceError.normalize(error))
        }
    }

    func select(_ summary: PreparedCardSummary) async {
        guard visible else { return }
        let operation = SelectionID()
        lease = nil
        preview = Preview(operation: operation, summary: summary, card: nil, status: .loading)
        let generation = inputGeneration
        let document = delivery?.documentIdentifier()
        guard generation == inputGeneration, visible, preview?.operation == operation else {
            setStatus(.refused(.inputChanged), for: operation)
            return
        }
        guard let document else {
            setStatus(.refused(.unavailableInput), for: operation)
            return
        }
        lease = Lease(operation: operation, document: document, generation: generation)
        do {
            let storage = try await reader()
            guard confirmTarget(for: operation), !cancelled(operation) else { return }
            let current = try await storage.revalidate(cardID: summary.id, expectedVersion: summary.version)
            guard confirmTarget(for: operation), !cancelled(operation) else { return }
            guard current.id == summary.id, current.version == summary.version else {
                refuse(.sourceChanged, for: operation)
                return
            }
            guard Self.supports(current) else {
                refuse(.unsupportedContent, for: operation)
                return
            }
            preview = Preview(operation: operation, summary: summary, card: current, status: .ready)
        } catch {
            handle(error, operation: operation)
        }
    }

    func insert() async {
        guard canInsert, let selected = preview, let card = selected.card, let expected = lease else { return }
        let operation = selected.operation
        setStatus(.checking, for: operation)
        do {
            let storage = try await reader()
            guard confirmTarget(for: operation), !cancelled(operation) else { return }
            let current = try await storage.revalidate(cardID: card.id, expectedVersion: card.version)
            guard confirmTarget(for: operation), !cancelled(operation) else { return }
            guard Self.matches(current, card) else {
                refuse(.sourceChanged, for: operation)
                return
            }
            let sent = delivery?.insert(current.body, document: expected.document) { [weak self] in
                guard let self, visible, !Task.isCancelled,
                      inputGeneration == expected.generation,
                      lease?.operation == operation,
                      preview?.operation == operation, preview?.status == .checking else { return false }
                lease = nil
                return true
            } ?? false
            if sent {
                setStatus(.sent, for: operation)
                return
            }
            if preview?.operation == operation, preview?.status == .checking {
                refuse(.deliveryRefused, for: operation)
            }
        } catch {
            handle(error, operation: operation)
        }
    }

    private func reader() async throws -> any WorkspaceStorage {
        if let suppliedStorage { return suppliedStorage }
        return try await PreparedKeyboardRepositoryFactory.open()
    }

    private static func supports(_ card: TextCard) -> Bool {
        card.pinned && card.deletedAt == nil
            && !card.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(card.usesVariables && !TextTemplate(card.body).names.isEmpty)
    }

    private static func matches(_ current: TextCard, _ selected: TextCard) -> Bool {
        current.id == selected.id && current.version == selected.version && supports(current)
            && current.body.utf8.elementsEqual(selected.body.utf8)
    }

    private func confirmTarget(for operation: SelectionID) -> Bool {
        guard visible, let held = lease, held.operation == operation,
              held.generation == inputGeneration, preview?.operation == operation else { return false }
        let document = delivery?.documentIdentifier()
        guard lease?.operation == operation, held.generation == inputGeneration, visible else { return false }
        guard let document else {
            refuse(.unavailableInput, for: operation)
            return false
        }
        guard document == held.document else {
            inputGeneration = InputGeneration()
            refuse(.inputChanged, for: operation)
            return false
        }
        return true
    }

    private func cancelled(_ operation: SelectionID) -> Bool {
        guard Task.isCancelled else { return false }
        refuse(.cancelled, for: operation)
        return true
    }

    private func handle(_ error: any Error, operation: SelectionID) {
        guard preview?.operation == operation, lease?.operation == operation else { return }
        if Task.isCancelled || error is CancellationError {
            refuse(.cancelled, for: operation)
            return
        }
        refuse(.storage(WorkspaceError.normalize(error)), for: operation)
    }

    private func refuse(_ reason: Refusal, for operation: SelectionID) {
        guard preview?.operation == operation else { return }
        lease = nil
        setStatus(.refused(reason), for: operation)
    }

    private func revoke(_ reason: Refusal) {
        lease = nil
        guard let preview, preview.status != .sent else { return }
        setStatus(.refused(reason), for: preview.operation)
    }

    private func setStatus(_ status: PreviewStatus, for operation: SelectionID) {
        guard var current = preview, current.operation == operation else { return }
        current.status = status
        preview = current
    }

    private func finishCancelledLoad(_ request: LoadGeneration) {
        if request == loadGeneration { listing = .idle }
    }
}

private enum PreparedKeyboardRepositoryFactory {
    @concurrent
    static func open() async throws -> WorkspaceRepository {
        try WorkspaceRepository(readOnly: true)
    }
}
