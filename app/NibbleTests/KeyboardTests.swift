import Foundation
import Testing
import Tasking
@testable import Nibble

@Suite("Keyboard storage")
struct KeyboardStorageTests {
    @Test func absentDatabaseIsNotCreated() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let reader = KeyboardReader(location: { files.url })
        await #expect(throws: KeyboardReadError.self) { try await reader.page(KeyboardRequest()) }
        #expect(!FileManager.default.fileExists(atPath: files.url.path))
    }

    @Test func savedPagesExcludeDraftsAndTrashAndRemainBounded() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        var ids: Set<UUID> = []
        for number in 0..<53 { ids.insert(try await create(files.store, body: "本文 \(number)")) }
        let pinned = try #require(ids.first)
        try await files.store.setPinned(true, id: pinned)
        let deleted = try await create(files.store, body: "削除済み")
        try await files.store.setDeleted(true, id: deleted)
        _ = try await files.store.beginDraft(body: "下書き")
        let reader = KeyboardReader(location: { files.url })
        let first = try await reader.page(KeyboardRequest())
        let second = try await reader.page(KeyboardRequest(offset: 50))
        #expect(first.items.count == 50 && first.hasMore && first.items.first?.id == pinned)
        #expect(second.items.count == 3 && !second.hasMore)
        #expect(Set((first.items + second.items).map(\.id)) == ids)
        #expect(try await reader.page(KeyboardRequest(filter: .pinned)).items.map(\.id) == [pinned])
        #expect(try await files.store.drafts().count == 1)
    }

    @Test func exactBodyIsReadAtUseAndChangesAreRejected() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let original = "  日本語 か\u{3099}\0\n\t👩🏽‍💻  "
        let id = try await create(files.store, body: original)
        let reader = KeyboardReader(location: { files.url })
        let item = try #require(try await reader.page(KeyboardRequest()).items.first)
        #expect(try await reader.body(for: item).utf8.elementsEqual(original.utf8))
        let writer = SnippetStore(location: files.url)
        var draft = try await writer.beginDraft(snippetID: id)
        draft.body = "更新後"
        _ = try await writer.save(draft)
        await #expect(throws: KeyboardReadError.self) { try await reader.body(for: item) }
        let updated = try #require(try await reader.page(KeyboardRequest()).items.first)
        #expect(try await reader.body(for: updated) == "更新後")
        try await writer.setDeleted(true, id: id)
        await #expect(throws: StoreError.missing) { try await reader.body(for: updated) }
    }

    @Test func readOnlyConnectionWorksAfterWriterClosesWithoutWritableFiles() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        // Confine the last writer to this scope; preserving WAL must survive its close.
        do {
            let db = try SQLiteDatabase(url: files.url)
            try SnippetSchema.prepare(db, at: files.url)
        }
        let paths = [files.url, URL(fileURLWithPath: files.url.path + "-wal"), URL(fileURLWithPath: files.url.path + "-shm")]
        let directory = files.url.deletingLastPathComponent()
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: path.path))
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: path.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            for path in paths { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path) }
        }
        let reader = KeyboardReader(location: { files.url })
        #expect(try await reader.page(KeyboardRequest()).items.isEmpty)
        let db = try SQLiteDatabase(url: files.url, access: .readOnly)
        #expect(throws: StoreError.database) { try db.execute("CREATE TABLE forbidden(id INTEGER)") }
    }

    @Test func unknownSchemaIsNotMigrated() async throws {
        let files = try TestDatabase()
        defer { files.removeFiles() }
        let db = try SQLiteDatabase(url: files.url)
        try db.execute("PRAGMA user_version=99")
        let reader = KeyboardReader(location: { files.url })
        await #expect(throws: StoreError.newerVersion) { try await reader.page(KeyboardRequest()) }
        #expect(try db.rows("PRAGMA user_version", []) { $0.int(0) } == [99])
    }
}

@Suite("Keyboard operation lifetime", .serialized)
@MainActor
struct KeyboardOperationTests {
    private let item = SnippetSummary(id: UUID(), title: "定型文", preview: "本文", pinned: false, revision: 1)

    @Test(arguments: [false, true])
    func overlappingReadsOfTheSameRequestKeepOnlyTheLatestExecution(fails: Bool) async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        model.activate()
        async let first: Void = model.refresh()
        await reader.pages.waitForRequests(1)
        async let second: Void = model.refresh()
        await reader.pages.waitForRequests(2)
        reader.pages.finish(1, .success(KeyboardPage(items: [item], hasMore: false)))
        await second
        reader.pages.finish(0, fails ? .failure(StoreError.database) : .success(KeyboardPage(items: [], hasMore: true)))
        await first
        #expect(model.page?.items == [item] && model.isCurrent && model.failure == nil)
    }

    @Test func anItemOutsideTheCurrentPageCannotTriggerAnEffect() async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        await prepare(model, reader: reader)
        let stale = SnippetSummary(id: item.id, title: item.title, preview: item.preview, pinned: false, revision: 0)
        await model.use(stale, as: .insert)
        await model.use(SnippetSummary(id: UUID(), title: "別ページ", preview: "", pinned: false, revision: 1), as: .copy)
        #expect(reader.bodies.count == 0 && effects.events.isEmpty && !model.isUsing)
    }

    @Test func cancelledReadCanBeRetriedWithoutReactivatingTheKeyboard() async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        let tasks = ViewTaskStore()
        model.activate()
        tasks.start(id: "read", lifetime: .screenBound) { _ in await model.refresh() }
        await reader.pages.waitForRequests(1)
        tasks.cancelAll()
        reader.pages.finish(0, .success(KeyboardPage(items: [item], hasMore: false)))
        await tasks.waitForIdle()
        #expect(!model.loading && !model.isCurrent && model.failure != nil)
        model.requestReload()
        async let retry: Void = model.refresh()
        await reader.pages.waitForRequests(2)
        reader.pages.finish(1, .success(KeyboardPage(items: [item], hasMore: false)))
        await retry
        #expect(model.isCurrent && model.failure == nil && model.page?.items == [item])
    }

    @Test(arguments: ["destination", "selection", "disappear", "reload", "cancel"])
    func copyHasItsOwnLifetimeAndDoesNotDependOnTheInsertionPoint(reason: String) async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        await prepare(model, reader: reader)
        let tasks = ViewTaskStore()
        tasks.start(id: "copy", lifetime: .screenBound) { _ in await model.use(item, as: .copy) }
        await reader.bodies.waitForRequests(1)
        switch reason {
        case "destination": effects.destination = KeyboardDestination(document: UUID(), revision: UUID())
        case "selection": effects.destination = KeyboardDestination(document: effects.destination.document, revision: UUID())
        case "disappear": model.deactivate()
        case "reload": model.requestReload()
        default: tasks.cancel(lifetime: .screenBound)
        }
        reader.bodies.finish(0, .success("原文"))
        await tasks.waitForIdle()
        #expect(effects.events == (["destination", "selection"].contains(reason) ? [.copy("原文")] : []))
        #expect(!model.isUsing)
    }

    @Test(arguments: [false, true])
    func lateReadCannotReplaceCurrentPage(fails: Bool) async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        model.activate()
        async let older: Void = model.refresh()
        await reader.pages.waitForRequests(1)
        model.select(.pinned)
        #expect(model.loading && !model.isCurrent && model.failure == nil)
        async let newer: Void = model.refresh()
        await reader.pages.waitForRequests(2)
        reader.pages.finish(1, .success(KeyboardPage(items: [item], hasMore: false)))
        await newer
        reader.pages.finish(0, fails ? .failure(StoreError.database) : .success(KeyboardPage(items: [], hasMore: true)))
        await older
        #expect(model.page?.items == [item] && model.isCurrent && model.failure == nil)
        model.select(.all)
        #expect(model.page?.items == [item] && model.loading && !model.isCurrent)
    }

    @Test(arguments: ["destination", "selection", "disappear", "reload", "cancel", "permission"])
    func lateUseCannotReachAnInvalidDestination(reason: String) async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        await prepare(model, reader: reader)
        let tasks = ViewTaskStore()
        tasks.start(id: "use", lifetime: .screenBound) { _ in await model.use(item, as: reason == "permission" ? .copy : .insert) }
        await reader.bodies.waitForRequests(1)
        await model.use(item, as: .insert) // Duplicate must not start another read.
        #expect(reader.bodies.count == 1)
        switch reason {
        case "destination": effects.destination = KeyboardDestination(document: UUID(), revision: UUID())
        case "selection": effects.destination = KeyboardDestination(document: effects.destination.document, revision: UUID())
        case "disappear": model.deactivate()
        case "reload": model.requestReload()
        case "cancel": tasks.cancelAll()
        default: effects.canCopy = false
        }
        reader.bodies.finish(0, .success("遅い本文"))
        await tasks.waitForIdle()
        #expect(effects.events.isEmpty && !model.isUsing)
        if reason == "cancel" {
            tasks.start(id: "retry", lifetime: .screenBound) { _ in await model.use(item, as: .insert) }
            await reader.bodies.waitForRequests(2)
            reader.bodies.finish(1, .success("再実行"))
            await tasks.waitForIdle()
            #expect(effects.events == [.insert("再実行")])
        }
    }

    @Test func insertDoesNotRequireFullAccessAndCopyIsAnIndependentEffect() async {
        let reader = KeyboardGateReader()
        let effects = RecordingKeyboardEffects()
        let model = KeyboardModel(reader: reader, effects: effects)
        await prepare(model, reader: reader)
        effects.canCopy = false
        await model.use(item, as: .copy)
        #expect(reader.bodies.count == 0 && model.message != nil)
        let tasks = ViewTaskStore()
        let original = "  か\u{3099}\n👩🏽‍💻  "
        tasks.start(id: "insert", lifetime: .screenBound) { _ in await model.use(item, as: .insert) }
        await reader.bodies.waitForRequests(1)
        reader.bodies.finish(0, .success(original))
        await tasks.waitForIdle()
        #expect(effects.events == [.insert(original)])
        effects.canCopy = true
        tasks.start(id: "copy", lifetime: .screenBound) { _ in await model.use(item, as: .copy) }
        await reader.bodies.waitForRequests(2)
        reader.bodies.finish(1, .success(original))
        await tasks.waitForIdle()
        #expect(effects.events == [.insert(original), .copy(original)])
    }

    private func prepare(_ model: KeyboardModel, reader: KeyboardGateReader) async {
        model.activate()
        async let load: Void = model.refresh()
        await reader.pages.waitForRequests(1)
        reader.pages.finish(0, .success(KeyboardPage(items: [item], hasMore: false)))
        await load
    }
}

@MainActor private final class RecordingKeyboardEffects: KeyboardEffects {
    enum Event: Equatable { case insert(String), copy(String) }
    var destination = KeyboardDestination(document: UUID(), revision: UUID())
    var canCopy = true
    var events: [Event] = []
    func insert(_ text: String) { events.append(.insert(text)) }
    func copy(_ text: String) { events.append(.copy(text)) }
    func dismiss() { }
}

@MainActor private final class KeyboardGateReader: KeyboardReading {
    let pages = KeyboardReadGate<KeyboardPage>()
    let bodies = KeyboardReadGate<String>()
    func page(_ request: KeyboardRequest) async throws -> KeyboardPage { try await pages.read() }
    func body(for item: SnippetSummary) async throws -> String { try await bodies.read() }
}

@MainActor private final class KeyboardReadGate<Value: Sendable> {
    private var pending: [CheckedContinuation<Value, any Error>?] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
    var count: Int { pending.count }
    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            if let waiter, pending.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }
    func waitForRequests(_ count: Int) async {
        guard pending.count < count else { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }
    func finish(_ index: Int, _ result: Result<Value, any Error>) {
        let continuation = pending[index]
        pending[index] = nil
        continuation?.resume(with: result)
    }
}
