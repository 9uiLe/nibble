import Foundation
import Testing
@testable import Nibble

@Suite("Prepared fixed text reaches only its confirmed input destination")
@MainActor
struct PreparedKeyboardTests {
    @Test func concurrentAndRepeatedConfirmationSendsTheLiteralBytesOnce() async throws {
        let body = "  {{literal}}\r\nか\u{3099}\t👩🏽‍💻\0  "
        let card = TextCard(title: "原文", body: body, pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        await model.refresh()
        await model.select(Self.summary(card))
        #expect(model.canInsert)
        #expect(model.preview?.card?.body.utf8.elementsEqual(body.utf8) == true)
        let gate = PreparedKeyboardGate()
        await source.pauseNextValidation(at: gate)
        async let first: Void = model.insert()
        await gate.waitUntilEntered()
        await model.insert()
        await gate.release()
        await first
        await model.insert()
        #expect(delivery.bodies.count == 1)
        #expect(delivery.bodies.first?.utf8.elementsEqual(body.utf8) == true)
        #expect(model.preview?.status == .sent && !model.canInsert)
        #expect(await source.writeAttempts == 0)
    }

    @Test func returningFromBToADoesNotRestoreAnOldPermission() async {
        let card = TextCard(title: "固定文", body: "送る内容", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let originalDocument = delivery.document
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: true)
        await model.select(Self.summary(card))
        delivery.document = UUID()
        model.inputChanged()
        delivery.document = originalDocument
        model.inputChanged()
        await model.insert()
        #expect(delivery.bodies.isEmpty)
        #expect(model.preview?.status == .refused(.inputChanged))
        #expect(model.preview?.card?.body == card.body)
        await model.select(Self.summary(card))
        await model.insert()
        #expect(delivery.bodies == [card.body])
    }

    @Test func aDestinationChangeDuringTheFullBodyReadCannotAuthorizeItsLateResult() async {
        let card = TextCard(title: "固定文", body: "途中で入力先を変更", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        let gate = PreparedKeyboardGate()
        await source.pauseNextValidation(at: gate)
        async let selecting: Void = model.select(Self.summary(card))
        await gate.waitUntilEntered()
        model.inputChanged()
        await gate.release()
        await selecting
        await model.insert()
        #expect(model.preview?.status == .refused(.inputChanged))
        #expect(!model.canInsert && delivery.bodies.isEmpty)
    }

    @Test func aSourceEditWhileConfirmationWaitsPreservesThePreviewAndSendsNothing() async {
        let card = TextCard(title: "固定文", body: "確認した旧内容", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        await model.select(Self.summary(card))
        let gate = PreparedKeyboardGate()
        await source.pauseNextValidation(at: gate)
        async let inserting: Void = model.insert()
        await gate.waitUntilEntered()
        await source.replace([TextCard(id: card.id, title: card.title, body: "編集された新内容",
                                      version: card.version + 1, pinned: true)])
        await gate.release()
        await inserting
        #expect(delivery.bodies.isEmpty)
        #expect(model.preview?.card?.body == card.body)
        #expect(model.preview?.status == .refused(.storage(.conflict)))
    }

    @Test func pinnedAndVariableEligibilityAreCheckedAgainBeforeDelivery() async {
        let card = TextCard(title: "固定文", body: "{{名前}}", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        await model.select(Self.summary(card))
        await source.replace([TextCard(id: card.id, title: card.title, body: card.body,
                                      version: card.version, pinned: false)])
        await model.insert()
        #expect(delivery.bodies.isEmpty && !model.canInsert)
        await source.replace([card])
        await model.select(Self.summary(card))
        await source.replace([TextCard(id: card.id, title: card.title, body: card.body,
                                      usesVariables: true, version: card.version, pinned: true)])
        await model.insert()
        #expect(delivery.bodies.isEmpty && !model.canInsert)
    }

    @Test func nilAndReentrantDocumentGettersNeverGrantOrReusePermission() async {
        let card = TextCard(title: "固定文", body: "安全な入力先だけ", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        delivery.document = nil
        await model.select(Self.summary(card))
        #expect(model.preview?.status == .refused(.unavailableInput))
        delivery.document = UUID()
        delivery.onIdentifierRead = { model.inputChanged() }
        await model.select(Self.summary(card))
        #expect(model.preview?.status == .refused(.inputChanged))
        await model.select(Self.summary(card))
        delivery.onFinalGetter = { model.inputChanged() }
        await model.insert()
        #expect(delivery.bodies.isEmpty && !model.canInsert)
        #expect(model.preview?.status == .refused(.inputChanged))
    }

    @Test func cancellationDismissalAndLeavingTheKeyboardHaveNoExternalEffect() async {
        let card = TextCard(title: "固定文", body: "送信しない内容", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        await model.select(Self.summary(card))
        let gate = PreparedKeyboardGate()
        await source.pauseNextValidation(at: gate)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.insert() }
            await gate.waitUntilEntered()
            group.cancelAll()
            await gate.release()
            await group.waitForAll()
        }
        #expect(model.preview?.status == .refused(.cancelled))
        await model.select(Self.summary(card))
        model.closePreview()
        await model.insert()
        await model.select(Self.summary(card))
        model.deactivate()
        model.activate(needsInputModeSwitchKey: false)
        await model.insert()
        #expect(delivery.bodies.isEmpty && !model.canInsert)
        #expect(model.preview?.card?.body == card.body)
    }

    @Test func aLateSelectionCannotReplaceTheNewerConfirmedFullBody() async {
        let first = TextCard(title: "一件目", body: "遅れて返る本文", pinned: true)
        let second = TextCard(title: "二件目", body: "選び直した本文", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [first, second])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        let gate = PreparedKeyboardGate()
        await source.pauseNextValidation(at: gate)
        async let oldSelection: Void = model.select(Self.summary(first))
        await gate.waitUntilEntered()
        await model.select(Self.summary(second))
        await gate.release()
        await oldSelection
        #expect(model.preview?.card?.id == second.id && model.canInsert)
        await model.insert()
        #expect(delivery.bodies == [second.body])
    }

    @Test func aLateListCannotReplaceANewerLoadAndLongTextIsLoadedOnlyAfterSelection() async {
        let old = TextCard(title: "古い一覧", body: "古い内容", pinned: true)
        let long = TextCard(title: "長文", body: String(repeating: "日本語👩🏽‍💻\n", count: 10_000), pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [old])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        let gate = PreparedKeyboardGate()
        await source.pauseNextList(at: gate)
        async let oldLoad: Void = model.refresh()
        await gate.waitUntilEntered()
        await source.replace([long])
        await model.refresh()
        await gate.release()
        await oldLoad
        guard case .cards(let cards) = model.listing else {
            Issue.record("The latest completed summary list must remain available")
            return
        }
        #expect(cards.map(\.id) == [long.id])
        #expect(await source.fullBodyReads == 0)
        await model.select(Self.summary(long))
        #expect(model.preview?.card?.body.utf8.elementsEqual(long.body.utf8) == true)
        #expect(model.canInsert)
    }

    @Test func aReadFailureCanBeRetriedWithoutRequestingWriteCapabilities() async {
        let card = TextCard(title: "固定文", body: "読込を再試行", pinned: true)
        let source = PreparedKeyboardStorageProbe(cards: [card])
        let delivery = PreparedKeyboardDeliverySpy()
        let model = PreparedKeyboardModel(storage: source, delivery: delivery)
        model.activate(needsInputModeSwitchKey: false)
        await source.failNextList()
        await model.refresh()
        guard case .failed(.unavailable) = model.listing else {
            Issue.record("The failed read must be visible")
            return
        }
        await model.refresh()
        guard case .cards(let cards) = model.listing else {
            Issue.record("Retry must complete the read")
            return
        }
        #expect(cards.map(\.id) == [card.id])
        #expect(await source.writeAttempts == 0)
        #expect(delivery.bodies.isEmpty)
    }

    private static func summary(_ card: TextCard) -> PreparedCardSummary {
        PreparedCardSummary(id: card.id, title: card.title, preview: String(card.body.prefix(180)),
                            version: card.version, modifiedAt: card.modifiedAt, originTitle: card.originTitle)
    }
}

@MainActor
private final class PreparedKeyboardDeliverySpy: PreparedKeyboardDelivery {
    var document: UUID? = UUID()
    var onIdentifierRead: (() -> Void)?
    var onFinalGetter: (() -> Void)?
    private(set) var bodies: [String] = []

    func documentIdentifier() -> UUID? {
        let callback = onIdentifierRead
        onIdentifierRead = nil
        callback?()
        return document
    }

    func insert(_ text: String, document expected: UUID, admission: () -> Bool) -> Bool {
        let current = document
        let callback = onFinalGetter
        onFinalGetter = nil
        callback?()
        guard current == expected, admission() else { return false }
        bodies.append(text)
        return true
    }

    func dismiss() {}
}

private actor PreparedKeyboardGate {
    private var entered = false
    private var released = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func pause() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor PreparedKeyboardStorageProbe: WorkspaceStorage {
    private var cards: [TextCard]
    private var validationGate: PreparedKeyboardGate?
    private var listGate: PreparedKeyboardGate?
    private var listFails = false
    private(set) var writeAttempts = 0
    private(set) var fullBodyReads = 0

    init(cards: [TextCard]) { self.cards = cards }
    func replace(_ cards: [TextCard]) { self.cards = cards }
    func pauseNextValidation(at gate: PreparedKeyboardGate) { validationGate = gate }
    func pauseNextList(at gate: PreparedKeyboardGate) { listGate = gate }
    func failNextList() { listFails = true }

    func keyboardSummaries(limit: Int) async throws -> [PreparedCardSummary] {
        if listFails {
            listFails = false
            throw WorkspaceError.unavailable
        }
        let result = cards.filter { $0.pinned && $0.deletedAt == nil }.prefix(limit).map {
            PreparedCardSummary(id: $0.id, title: $0.title, preview: String($0.body.prefix(180)),
                                version: $0.version, modifiedAt: $0.modifiedAt, originTitle: $0.originTitle)
        }
        if let gate = listGate {
            listGate = nil
            await gate.pause()
        }
        return result
    }

    func revalidate(cardID: UUID, expectedVersion: Int) async throws -> TextCard {
        fullBodyReads += 1
        if let gate = validationGate {
            validationGate = nil
            await gate.pause()
        }
        let current = try card(id: cardID)
        guard current.deletedAt == nil else { throw WorkspaceError.missingCard }
        guard current.version == expectedVersion else { throw WorkspaceError.conflict }
        return current
    }

    func card(id: UUID) throws -> TextCard {
        guard let card = cards.first(where: { $0.id == id }) else { throw WorkspaceError.missingCard }
        return card
    }

    func list(query: WorkspaceQuery) throws -> WorkspacePage { throw WorkspaceError.readOnly }
    func drafts() throws -> [WorkDraft] { throw WorkspaceError.readOnly }
    func draft(id: UUID) throws -> WorkDraft { throw WorkspaceError.readOnly }
    func beginDraft(title: String, body: String) throws -> WorkDraft { writeAttempts += 1; throw WorkspaceError.readOnly }
    func editingDraft(cardID: UUID) throws -> WorkDraft { writeAttempts += 1; throw WorkspaceError.readOnly }
    func preparationDraft(cardID: UUID) throws -> WorkDraft { writeAttempts += 1; throw WorkspaceError.readOnly }
    func checkpoint(_ draft: WorkDraft) throws -> WorkDraft { writeAttempts += 1; throw WorkspaceError.readOnly }
    func publish(_ draft: WorkDraft) throws -> TextCard { writeAttempts += 1; throw WorkspaceError.readOnly }
    func discardDraft(id: UUID, expectedSequence: Int) throws { writeAttempts += 1; throw WorkspaceError.readOnly }
    func setPinned(_ pinned: Bool, cardID: UUID, expectedVersion: Int) throws -> TextCard { writeAttempts += 1; throw WorkspaceError.readOnly }
    func rename(cardID: UUID, expectedVersion: Int, title: String) throws -> TextCard { writeAttempts += 1; throw WorkspaceError.readOnly }
    func trash(cardID: UUID, expectedVersion: Int) throws -> TextCard { writeAttempts += 1; throw WorkspaceError.readOnly }
    func restore(cardID: UUID, expectedVersion: Int) throws -> TextCard { writeAttempts += 1; throw WorkspaceError.readOnly }
}
