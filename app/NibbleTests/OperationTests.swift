import Foundation
import Testing
import Tasking
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Application contracts", .serialized)
    @MainActor
    struct ApplicationContractTests {
        @Test func retainedPagesAndSearchHaveIndependentBudgets() throws {
            var state = LibraryReadState(surface: .library)
            let first = state.begin()
            #expect(first.requests.map(\.filter) == [.all, .pinned, .drafts])
            let pinned = SnippetSummary(id: UUID(), title: "固定", preview: "本文", pinned: true, revision: 1)
            let initialAccepted = try state.accept([LibraryPage(), LibraryPage(items: [pinned]), LibraryPage()], from: first)
            try #require(initialAccepted)
            state.end(first)
            state.select(.pinned)
            #expect(state.snapshot?.page.items == [pinned] && !state.loading && state.demand == nil)
            state.showMore()
            let expanded = state.begin()
            #expect(expanded.requests.map(\.limit) == [100, 200, 100])
            let expansionAccepted = try state.accept([LibraryPage(), LibraryPage(items: [pinned]), LibraryPage()], from: expanded)
            try #require(expansionAccepted)
            state.end(expanded)
            state.search("固定")
            #expect(state.request.filter == .all && state.request.limit == 100)
            let search = state.begin()
            #expect(search.requests.count == 1)
            let searchAccepted = try state.accept([LibraryPage(items: [pinned])], from: search)
            try #require(searchAccepted)
            state.end(search)
            state.search("")
            #expect(state.selection == .pinned && state.request.limit == 200)
            #expect(state.snapshot?.page.items == [pinned] && state.demand == nil)
            state.showAll()
            #expect(state.selection == .all && state.request.limit == 100)
        }

        @Test func collectionRefreshSurvivesSearchDismissalButOlderBatchesCannotOverwriteIt() throws {
            var state = LibraryReadState(surface: .library)
            state.search("検索")
            let mutationRead = state.begin(includingCollections: true)
            state.search("")
            let newerRead = state.begin()
            let newest = LibraryPage(counts: LibraryCounts(saved: 3))
            let newestAccepted = try state.accept([newest, LibraryPage(), LibraryPage()], from: newerRead)
            try #require(newestAccepted)
            state.end(newerRead)
            let obsoleteAccepted = try state.accept([LibraryPage(), LibraryPage(), LibraryPage(), LibraryPage()], from: mutationRead)
            #expect(!obsoleteAccepted)
            state.end(mutationRead)
            #expect(state.snapshot?.page.counts.saved == 3)

            state.search("検索")
            let outstanding = state.begin(includingCollections: true)
            state.search("")
            let updated = LibraryPage(counts: LibraryCounts(saved: 4))
            let refreshAccepted = try state.accept([updated, LibraryPage(), LibraryPage(), LibraryPage()], from: outstanding)
            try #require(refreshAccepted)
            state.end(outstanding)
            #expect(state.snapshot?.page.counts.saved == 4 && !state.loading)
        }

        @Test func malformedBatchCannotPublishPartialCollections() throws {
            var state = LibraryReadState(surface: .library)
            let batch = state.begin()
            var refusal: StoreError?
            do { _ = try state.accept([LibraryPage()], from: batch) }
            catch { refusal = error as? StoreError }
            #expect(refusal == .unavailable)
            state.complete(.failed(StoreError.unavailable), from: batch)
            state.end(batch)
            #expect(state.snapshot == nil && state.error as? StoreError == .unavailable)
            #expect(!state.loading)
        }

        @Test(arguments: [false, true])
        func delayedReadCannotReplaceANewerSuccess(oldFails: Bool) async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let reader = ApplicationLibraryReader()
            let model = LibraryModel(store: files.store, libraryReader: reader)
            let tasks = ViewTaskStore()
            tasks.start(id: "old", lifetime: .sceneBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.gate.waitForAdmissions(1)
            model.query = "新しい検索"
            tasks.start(id: "new", lifetime: .sceneBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.gate.waitForAdmissions(2)
            let row = SnippetSummary(id: UUID(), title: "結果", preview: "全文", pinned: false, revision: 1)
            reader.gate.resolve(1, .success([LibraryPage(items: [row])]))
            await reader.gate.waitForReturns(1)
            reader.gate.resolve(0, oldFails ? .failure(StoreError.database) : .success([LibraryPage(), LibraryPage(), LibraryPage()]))
            await tasks.waitForIdle()
            #expect(model.items == [row] && model.contentIsCurrent && !model.loading)
            #expect(model.failure == nil && !model.showsEmptyState)
        }

        @Test func cancellationRetainsTheOldPageAndAllowsRetry() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "保存済み")
            let reader = ApplicationLibraryReader()
            let model = LibraryModel(store: files.store, libraryReader: reader)
            let tasks = ViewTaskStore()
            tasks.start(id: "read", lifetime: .sceneBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.gate.waitForAdmissions(1)
            let original = try await files.store.libraries(reader.requests[0])
            reader.gate.resolve(0, .success(original))
            await tasks.waitForIdle()
            model.query = "検索中"
            tasks.start(id: "read", lifetime: .sceneBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.gate.waitForAdmissions(2)
            tasks.cancel(lifetime: .sceneBound)
            reader.gate.resolve(1, .success([LibraryPage()]))
            await tasks.waitForIdle()
            #expect(model.items.map(\.id) == [id] && !model.contentIsCurrent)
            #expect(model.loadingInterrupted && !model.loading && model.failure == nil)
            tasks.start(id: "retry", lifetime: .sceneBound, policy: .ignoreNew) { _ in await model.refresh() }
            await reader.gate.waitForAdmissions(3)
            reader.gate.resolve(2, .success([LibraryPage()]))
            await tasks.waitForIdle()
            #expect(model.showsEmptyState && !model.loadingInterrupted)
        }

        @Test func copyCommitsOSOutputAndRetriesOnlyItsUsageRecord() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let text = "\tか\u{3099}\r\n\0😀\n"
            let id = try await create(files.store, title: "使う本文", body: text)
            let effects = RecordingLibraryEffects()
            let recorder = ApplicationUsageRecorder(store: files.store)
            let model = LibraryModel(store: files.store, effects: effects, usageRecorder: recorder)
            await model.copy(id)
            #expect(effects.events.filter { if case .copy = $0 { true } else { false } } == [.copy(text)])
            #expect(model.notice?.result == .copied && model.failure?.recovery == .retryUsage)
            #expect(try await files.store.search().first?.usage?.count == 0)
            await model.retryUsageRecording()
            #expect(recorder.attempts.count == 2 && recorder.attempts[0].id == recorder.attempts[1].id)
            #expect(effects.events.filter { if case .copy = $0 { true } else { false } }.count == 1)
            #expect(try await files.store.search().first?.usage?.count == 1)
            #expect(model.failure == nil && model.items.first?.usage?.count == 1)
        }

        @Test func returningFromCopyHasAlreadyWrittenOnlyTheBodyToThePasteboard() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let text = " \tが\r\nか\u{3099}\0😀 "
            let id = try await create(files.store, title: "本文へ含めないタイトル", body: text)
            UIPasteboard.general.string = "置き換えるダミー"
            let model = LibraryModel(store: files.store, effects: SystemLibraryEffects())
            await model.copy(id)
            let result = try #require(UIPasteboard.general.string)
            #expect(SnippetText.hasSameBytes(result, text))
            #expect(try await files.store.snippet(id).usage.count == 1)
        }

        @Test func variablesRequireConfirmationRevalidateOriginalAndNeverEditSavedText() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let original = "{{相手}}さんへ\n{{相手}}さん、こんにちは"
            let id = try await create(files.store, title: "返信", body: original)
            let effects = RecordingLibraryEffects()
            let model = LibraryModel(store: files.store, effects: effects)
            await model.refresh()
            await model.copy(id)
            let pending = try #require(model.variableCopy)
            #expect(pending.title == "返信" && effects.events.isEmpty)
            await model.completeVariableCopy(id: pending.id, values: [:])
            #expect(model.variableCopy != nil && effects.events.isEmpty)
            model.cancelVariableCopy()
            #expect(effects.events.isEmpty)
            await model.copy(id)
            let confirmed = try #require(model.variableCopy)
            await model.completeVariableCopy(id: confirmed.id, values: testVariableValues(["相手": "田中"]))
            #expect(effects.events.contains(.copy("田中さんへ\n田中さん、こんにちは")))
            #expect(try await files.store.savedBody(id).utf8.elementsEqual(original.utf8))
            await model.copy(id)
            let stale = try #require(model.variableCopy)
            var update = try await files.store.editingDraft(for: id)
            update.body = "別の本文"
            try await files.store.save(update)
            let before = effects.events.count
            await model.completeVariableCopy(id: stale.id, values: testVariableValues(["相手": "佐藤"]))
            #expect(effects.events.count == before && model.failure?.reason == .conflict)
        }

        @Test func editorSeparatesInputAnalysisPersistenceAndConflictRecovery() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let id = try await create(files.store, body: "以前の本文")
            let draft = try await files.store.editingDraft(for: id)
            let editor = EditorModel(draft: draft, store: files.store)
            editor.title = "新しい題"
            #expect(editor.bodyRevision == 0 && editor.draft.sequence == 1)
            editor.body = "か\u{3099}\r\n編集"
            #expect(editor.bodyRevision == 1 && editor.draft.sequence == 2)
            #expect(try await files.store.draft(draft.id).title.isEmpty)
            await editor.persist(editor.draft)
            #expect(try await files.store.draft(draft.id).title == "新しい題")
            try await files.store.setPinned(true, id: id)
            #expect(!(await editor.finish(.save)))
            #expect(editor.phase == .editing && editor.failure?.canSaveAsNew == true)
            let input = editor.body
            #expect(await editor.finish(.saveAsNew))
            #expect(editor.phase == .finished)
            #expect(try await files.store.search().count == 2)
            editor.body = "終了後の入力"
            #expect(SnippetText.hasSameBytes(editor.body, input))
        }

        @Test func aFinishingEditorRejectsInputAndLateAutosaveCannotResurrectTheDraft() async throws {
            let files = try TestDatabase()
            defer { files.removeFiles() }
            let draft = try await files.store.beginDraft(body: "編集中")
            let store = ApplicationDraftEditor(store: files.store)
            let model = EditorModel(draft: draft, store: store)
            model.body = "確定する本文"
            let tasks = ViewTaskStore()
            tasks.start(id: "autosave", lifetime: .screenBound, policy: .ignoreNew) { _ in await model.persist(model.draft) }
            await store.updateGate.waitForAdmissions(1)
            #expect(await model.finish(.save))
            store.updateGate.resolve(0, .success(true))
            await tasks.waitForIdle()
            #expect(try await files.store.drafts().isEmpty)
            #expect(try await files.store.search().first?.preview == "確定する本文")
            #expect(model.phase == .finished && model.failure == nil)
        }
    }
}

@MainActor
final class ApplicationGate<Value: Sendable> {
    private var continuations: [CheckedContinuation<Value, any Error>?] = []
    private var admissions: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returns: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var returned = 0

    func read() async throws -> Value {
        do {
            let value = try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
                resumeSatisfied(&admissions, count: continuations.count)
            }
            returned += 1
            resumeSatisfied(&returns, count: returned)
            return value
        } catch {
            returned += 1
            resumeSatisfied(&returns, count: returned)
            throw error
        }
    }

    func waitForAdmissions(_ count: Int) async {
        guard continuations.count < count else { return }
        await withCheckedContinuation { admissions.append((count, $0)) }
    }

    func waitForReturns(_ count: Int) async {
        guard returned < count else { return }
        await withCheckedContinuation { returns.append((count, $0)) }
    }

    func resolve(_ index: Int, _ result: Result<Value, any Error>) {
        let continuation = continuations[index]
        continuations[index] = nil
        continuation?.resume(with: result)
    }

    private func resumeSatisfied(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int) {
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        for (_, waiter) in ready { waiter.resume() }
    }
}

@MainActor
private final class ApplicationLibraryReader: LibraryReading {
    let gate = ApplicationGate<[LibraryPage]>()
    private(set) var requests: [[LibraryRequest]] = []
    func libraries(_ requests: [LibraryRequest]) async throws -> [LibraryPage] {
        self.requests.append(requests)
        return try await gate.read()
    }
}

@MainActor
private final class ApplicationUsageRecorder: SnippetUsageRecording {
    let store: SnippetStore
    private(set) var attempts: [SnippetUse] = []
    init(store: SnippetStore) { self.store = store }
    func recordUse(_ use: SnippetUse) async throws {
        attempts.append(use)
        guard attempts.count > 1 else { throw StoreError.database }
        try await store.recordUse(use)
    }
}

@MainActor
private final class ApplicationDraftEditor: DraftEditing {
    let store: SnippetStore
    let updateGate = ApplicationGate<Bool>()
    init(store: SnippetStore) { self.store = store }
    func updateDraft(_ draft: Draft) async throws {
        _ = try await updateGate.read()
        try await store.updateDraft(draft)
    }
    func keepDraft(_ draft: Draft) async throws { try await store.keepDraft(draft) }
    func discardDraft(_ draft: Draft) async throws { try await store.discardDraft(draft) }
    func save(_ draft: Draft, mode: DraftSaveMode) async throws -> UUID { try await store.save(draft, mode: mode) }
}
