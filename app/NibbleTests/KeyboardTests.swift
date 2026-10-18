import Foundation
import Testing
import Tasking
@testable import Nibble

@Suite("Keyboard shared-store contract")
struct KeyboardStorageTests {
    @Test func readingNeverCreatesOrMigratesAStore() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let reader = KeyboardReader(location: { files.url })
        await #expect(throws: KeyboardReadError.notPrepared) { try await reader.page(KeyboardRequest()) }
        #expect(!FileManager.default.fileExists(atPath: files.url.path))
        let database = try SQLiteDatabase(url: files.url)
        try database.execute("PRAGMA user_version=99")
        await #expect(throws: StoreError.newerVersion) { try await reader.page(KeyboardRequest()) }
        let unknown = SnippetSummary(id: UUID(), title: "", preview: "", pinned: false, revision: 1)
        await #expect(throws: StoreError.newerVersion) { try await reader.setPinned(true, for: unknown) }
        #expect(try database.rows("PRAGMA user_version", []) { try $0.int(0) } == [99])
    }

    @Test func pagesAreBoundedPinFirstAndNeverIncludeDraftOrDeletedText() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        var saved: Set<UUID> = []
        for number in 1...51 { saved.insert(try await create(files.store, body: "定型文 \(number)")) }
        let pin = try #require(saved.first)
        try await files.store.setPinned(true, id: pin)
        let removed = try await create(files.store, body: "削除する本文")
        try await files.store.mutate(.delete, id: removed)
        _ = try await files.store.beginDraft(body: "まだ利用しない入力")
        let reader = KeyboardReader(location: { files.url })
        let first = try await reader.page(KeyboardRequest())
        let last = try await reader.page(KeyboardRequest(offset: 50))
        #expect(first.items.count == 50 && first.hasMore && first.items.first?.id == pin)
        #expect(last.items.count == 1 && !last.hasMore)
        #expect(Set((first.items + last.items).map(\.id)) == saved)
        #expect(first.items.allSatisfy { $0.usage == nil })
        #expect(try await reader.page(KeyboardRequest(filter: .pinned)).items.map(\.id) == [pin])
    }

    @Test func bodyAndPinRevalidateRevisionWhilePreservingExactOriginal() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let text = " \tか\u{3099}\r\n\0👩🏽‍💻 "
        let id = try await create(files.store, title: "識別", body: text)
        let before = try await files.store.snippet(id)
        let reader = KeyboardReader(location: { files.url })
        let item = try #require(try await reader.page(KeyboardRequest()).items.first)
        #expect(try await reader.body(for: item).utf8.elementsEqual(text.utf8))
        let pinned = try await reader.setPinned(true, for: item)
        let after = try await files.store.snippet(id)
        #expect(pinned.pinned && after.revision > before.revision)
        #expect(after.updatedAt == before.updatedAt && after.title == before.title)
        #expect(SnippetText.hasSameBytes(after.body, text))
        await #expect(throws: KeyboardReadError.changed) { try await reader.body(for: item) }
        await #expect(throws: KeyboardReadError.changed) { try await reader.setPinned(false, for: item) }
        try await files.store.mutate(.delete, id: id)
        await #expect(throws: StoreError.missing) { try await reader.body(for: pinned) }
    }

    @Test func writerCloseLeavesTheFilesRequiredByReadOnlyWALReaders() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        do {
            let database = try SQLiteDatabase(url: files.url)
            try SnippetSchema.prepare(database, at: files.url)
        }
        let directory = files.url.deletingLastPathComponent()
        let paths = [files.url, URL(fileURLWithPath: files.url.path + "-wal"), URL(fileURLWithPath: files.url.path + "-shm")]
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            for path in paths { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path) }
        }
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: path.path))
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: path.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(try await KeyboardReader(location: { files.url }).page(KeyboardRequest()).items.isEmpty)
    }
}

extension UIIntegrationTests {
    @Suite("Keyboard provenance and completion", .serialized)
    @MainActor
    struct KeyboardOperationTests {
        @Test func insertionAndClipboardHaveDistinctPermissionsAndEffects() async throws {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            effects.canCopy = false
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .copy)
            #expect(model.notice?.result == .requiresFullAccess(.copy) && effects.output.isEmpty)
            await model.use(reader.item, as: .insert)
            #expect(effects.output == [.insert(reader.text)])
            #expect(model.notice?.insertedID == reader.item.id)
            effects.canCopy = true
            model.select(.pinned)
            await model.refresh()
            await model.use(reader.item, as: .copy)
            #expect(effects.output.last == .copy(reader.text))
            model.deactivate()
            model.activate()
            #expect(model.request.filter == .all && model.request.offset == 0)
        }

        @Test(arguments: ["document", "selection", "unavailable", "hidden", "reload", "cancel", "permission"])
        func suspendedUseCannotReachAnInvalidContext(change: String) async {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            reader.gateBodies = true
            let tasks = ViewTaskStore()
            let mode: KeyboardModel.Use = change == "permission" ? .copy : .insert
            tasks.start(id: "use", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.use(reader.item, as: mode) }
            await reader.bodies.waitForAdmissions(1)
            switch change {
            case "document": effects.destination = KeyboardDestination(document: UUID(), revision: UUID())
            case "selection": effects.destination = KeyboardDestination(document: effects.destination.document, revision: UUID())
            case "unavailable": effects.destination = KeyboardDestination(document: nil, revision: UUID())
            case "hidden": model.deactivate()
            case "reload": model.requestReload()
            case "cancel": tasks.cancel(lifetime: .screenBound)
            case "permission": effects.canCopy = false
            default: break
            }
            reader.bodies.resolve(0, .success(reader.text))
            await tasks.waitForIdle()
            #expect(effects.output.isEmpty && model.notice?.insertedID == nil)
        }

        @Test func variableConfirmationAllowsValueEditingButRejectsAnotherDocument() async throws {
            let reader = KeyboardProbeReader()
            reader.text = "こんにちは {{名前}} {{名前}}"
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            #expect(model.variableUse?.template.names.count == 1 && effects.holding)
            await model.completeVariableUse(values: [:])
            #expect(effects.output.isEmpty)
            await model.completeVariableUse(values: testVariableValues(["名前": "小林"]))
            #expect(effects.output == [.insert("こんにちは 小林 小林")] && !effects.holding)
            await model.use(reader.item, as: .insert)
            effects.destination = KeyboardDestination(document: UUID(), revision: UUID())
            await model.completeVariableUse(values: testVariableValues(["名前": "田中"]))
            #expect(effects.output.count == 1 && model.notice?.result == .inputChanged)
            await model.use(reader.item, as: .copy)
            model.cancelVariableUse()
            #expect(effects.output.count == 1 && !effects.holding)
        }

        @Test(arguments: [false, true])
        func valueEntryStaysPresentedThroughTheOSInsertionDecision(accepted: Bool) async throws {
            let reader = KeyboardProbeReader()
            reader.text = "原文 {{名前}}"
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            let pending = try #require(model.variableUse?.id)
            var presentedAtBoundary: [Bool] = []
            effects.onDestinationRead = { [weak model] in
                presentedAtBoundary.append(model?.variableUse?.id == pending && effects.holding)
            }
            var insertionDecisions = 0
            effects.onInsert = { [weak model] in
                insertionDecisions += 1
                presentedAtBoundary.append(model?.variableUse?.id == pending && effects.holding)
            }
            effects.acceptsInsertion = accepted
            await model.completeVariableUse(values: testVariableValues(["名前": "値"]))
            effects.onDestinationRead = nil
            effects.onInsert = nil
            #expect(!presentedAtBoundary.isEmpty && presentedAtBoundary.allSatisfy { $0 })
            #expect(insertionDecisions == 1)
            #expect(model.variableUse == nil && !effects.holding)
            #expect(effects.output == (accepted ? [.insert("原文 値")] : []))
            #expect(model.notice?.result == (accepted ? .inserted(reader.item.id) : .inputChanged))
        }

        @Test(arguments: [false, true])
        func anUnavailableDocumentNeverAllowsInsertion(variable: Bool) async {
            let reader = KeyboardProbeReader()
            if variable { reader.text = "原文 {{名前}}" }
            let effects = KeyboardProbeEffects()
            effects.destination = KeyboardDestination(document: nil, revision: UUID())
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            await model.completeVariableUse(values: testVariableValues(["名前": "値"]))
            #expect(effects.output.isEmpty && !effects.holding && model.variableUse == nil)
            #expect(model.notice?.result == .inputChanged)
        }

        @Test(arguments: ["document", "selection", "unavailable"])
        func aHostChangeDuringLocalValueEntryRejectsConfirmation(change: String) async {
            let reader = KeyboardProbeReader()
            reader.text = "原文 {{名前}}"
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            let document = change == "document" ? UUID() : effects.destination.document
            effects.destination = KeyboardDestination(document: change == "unavailable" ? nil : document, revision: UUID())
            await model.completeVariableUse(values: testVariableValues(["名前": "値"]))
            #expect(effects.output.isEmpty && !effects.holding && model.notice?.result == .inputChanged)
        }

        @Test func losingTheDestinationBeforeValueEntryDoesNotOpenOrSendTheOldOperation() async {
            let reader = KeyboardProbeReader()
            reader.text = "原文 {{名前}}"
            let effects = KeyboardProbeEffects()
            effects.acceptsHolding = false
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            await model.completeVariableUse(values: testVariableValues(["名前": "古い値"]))
            #expect(model.variableUse == nil && effects.output.isEmpty && !effects.holding)
            #expect(model.notice?.result == .inputChanged)
            effects.acceptsHolding = true
            await model.use(reader.item, as: .insert)
            await model.completeVariableUse(values: testVariableValues(["名前": "新しい値"]))
            #expect(effects.output == [.insert("原文 新しい値")])
        }

        @Test func refusalAtTheOSBoundaryCannotProduceSuccess() async {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            effects.acceptsInsertion = false
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            await model.use(reader.item, as: .insert)
            #expect(effects.output.isEmpty && model.notice?.result == .inputChanged)
            effects.destination = KeyboardDestination(document: nil, revision: UUID())
            await model.use(reader.item, as: .copy)
            #expect(effects.output == [.copy(reader.text)] && model.notice?.result == .copied)
        }

        @Test(arguments: [false, true])
        func aRequestInvalidatedWhileHoldingTheDestinationCannotOpenValueEntry(hidden: Bool) async {
            let reader = KeyboardProbeReader()
            reader.text = "原文 {{名前}}"
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            effects.onHold = {
                if hidden { model.deactivate() } else { model.select(.pinned) }
            }
            await model.use(reader.item, as: .insert)
            await model.completeVariableUse(values: testVariableValues(["名前": "古い値"]))
            #expect(model.variableUse == nil && !effects.holding && effects.output.isEmpty)
        }

        @Test func theLatestPageReadWinsAndCancellationCanRecover() async {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            reader.gatePages = true
            model.activate()
            let tasks = ViewTaskStore()
            tasks.start(id: "first", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.pages.waitForAdmissions(1)
            model.select(.pinned)
            tasks.start(id: "second", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.pages.waitForAdmissions(2)
            reader.pages.resolve(1, .success(KeyboardPage(items: [reader.item], hasMore: false)))
            await reader.pages.waitForReturns(1)
            reader.pages.resolve(0, .failure(StoreError.database))
            await tasks.waitForIdle()
            #expect(model.isCurrent && model.request.filter == .pinned && model.loadFailure == nil)
            tasks.start(id: "cancel", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.pages.waitForAdmissions(3)
            tasks.cancel(lifetime: .screenBound)
            reader.pages.resolve(2, .success(KeyboardPage(items: [], hasMore: false)))
            await tasks.waitForIdle()
            #expect(model.loadFailure == .cancelled && !model.loading)
            reader.gatePages = false
            await model.refresh()
            #expect(model.isCurrent && model.loadFailure == nil)
        }

        @Test func detailReadsNeverInsertAndLatePreviewCannotReplaceANewSelection() async throws {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            model.openDetail(reader.item)
            reader.gateBodies = true
            let tasks = ViewTaskStore()
            tasks.start(id: "old-preview", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.loadDetail() }
            await reader.bodies.waitForAdmissions(1)
            model.closeDetail()
            model.openDetail(reader.item)
            tasks.start(id: "new-preview", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.loadDetail() }
            await reader.bodies.waitForAdmissions(2)
            reader.bodies.resolve(1, .success("現在の全文"))
            await reader.bodies.waitForReturns(1)
            reader.bodies.resolve(0, .success("遅い全文"))
            await tasks.waitForIdle()
            #expect(model.detail?.body == "現在の全文" && effects.output.isEmpty)
            reader.gateBodies = false
            await model.use(try #require(model.detail?.item), as: .insert)
            #expect(effects.output == [.insert(reader.text)] && model.detail == nil)
        }

        @Test func changedRevisionInvalidatesTheFullTextBeforeItCanBeUsed() async throws {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            let oldItem = reader.item
            model.openDetail(oldItem)
            await model.loadDetail()
            reader.item = SnippetSummary(id: oldItem.id, title: oldItem.title, preview: "更新", pinned: false, revision: 2)
            await model.refresh()
            #expect(model.detail?.body == nil)
            #expect(model.detail?.error == .failed(.changed, .changed, detailIsOpen: true))
            await model.use(oldItem, as: .insert)
            #expect(effects.output.isEmpty)
            reader.text = "更新後の全文"
            await model.loadDetail()
            #expect(model.detail?.body == reader.text && model.detail?.item.revision == 2)
        }

        @Test func previewFailurePreservesTheSelectionWithoutProducingAnOSResult() async {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            model.activate()
            await model.refresh()
            model.openDetail(reader.item)
            reader.gateBodies = true
            let tasks = ViewTaskStore()
            tasks.start(id: "preview", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.loadDetail() }
            await reader.bodies.waitForAdmissions(1)
            reader.bodies.resolve(0, .failure(StoreError.database))
            await tasks.waitForIdle()
            #expect(model.detail?.item.id == reader.item.id)
            #expect(model.detail?.error == .failed(.preview, .store(.database), detailIsOpen: true))
            #expect(model.notice == nil && effects.output.isEmpty)
        }

        @Test func committedUnpinRemainsVisibleInDetailWhenPageReloadFails() async throws {
            let reader = KeyboardProbeReader()
            let effects = KeyboardProbeEffects()
            let model = KeyboardModel(reader: reader, effects: effects)
            reader.item = SnippetSummary(id: reader.item.id, title: "固定", preview: "本文", pinned: true, revision: 1)
            model.activate()
            model.select(.pinned)
            await model.refresh()
            model.openDetail(reader.item)
            await model.loadDetail()
            reader.gatePins = true
            reader.gatePages = true
            let tasks = ViewTaskStore()
            tasks.start(id: "pin", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.togglePin() }
            await reader.pins.waitForAdmissions(1)
            let updated = SnippetSummary(id: reader.item.id, title: "固定", preview: "本文", pinned: false, revision: 2)
            reader.pins.resolve(0, .success(updated))
            await reader.pages.waitForAdmissions(1)
            #expect(model.detail?.item == updated && model.detail?.body == reader.text)
            #expect(model.page?.items.isEmpty == true && model.notice?.result == .pinChanged(false))
            reader.pages.resolve(0, .failure(StoreError.database))
            await tasks.waitForIdle()
            #expect(model.detail?.item == updated && model.request.filter == .pinned)
            #expect(model.notice?.result == .failed(.reloadAfterPin, .store(.database), detailIsOpen: true))
        }
    }
}

@MainActor
private final class KeyboardProbeReader: KeyboardReading {
    var item = SnippetSummary(id: UUID(), title: "保存済み", preview: "本文", pinned: false, revision: 1)
    var text = "  本文\r\n\0😀  "
    var gatePages = false
    var gateBodies = false
    var gatePins = false
    let pages = ApplicationGate<KeyboardPage>()
    let bodies = ApplicationGate<String>()
    let pins = ApplicationGate<SnippetSummary>()
    func page(_ request: KeyboardRequest) async throws -> KeyboardPage {
        if gatePages { return try await pages.read() }
        return KeyboardPage(items: [item], hasMore: false)
    }
    func body(for item: SnippetSummary) async throws -> String {
        if gateBodies { return try await bodies.read() }
        return text
    }
    func setPinned(_ pinned: Bool, for item: SnippetSummary) async throws -> SnippetSummary {
        if gatePins { return try await pins.read() }
        return SnippetSummary(id: item.id, title: item.title, preview: item.preview, pinned: pinned, revision: item.revision + 1)
    }
}

@MainActor
private final class KeyboardProbeEffects: KeyboardEffects {
    enum Output: Equatable { case insert(String), copy(String) }
    private var currentDestination = KeyboardDestination(document: UUID(), revision: UUID())
    var onDestinationRead: (() -> Void)?
    var destination: KeyboardDestination {
        get {
            onDestinationRead?()
            return currentDestination
        }
        set { currentDestination = newValue }
    }
    var canCopy = true
    private(set) var output: [Output] = []
    private(set) var holding = false
    func copy(_ text: String) { output.append(.copy(text)) }
    var acceptsInsertion = true
    var onInsert: (() -> Void)?
    func insert(_ text: String, into expected: KeyboardDestination) -> Bool {
        onInsert?()
        guard acceptsInsertion, expected.document != nil, destination == expected else { return false }
        output.append(.insert(text))
        return true
    }
    func dismiss() { }
    var acceptsHolding = true
    var onHold: (() -> Void)?
    func holdInputDocument(_ expected: KeyboardDestination) -> Bool {
        onHold?()
        holding = acceptsHolding && expected.document != nil && destination == expected
        return holding
    }
    func releaseInputDocument() { holding = false }
}
