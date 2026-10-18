import Foundation
import Testing
@testable import Nibble

@Suite("Editing session durability")
struct DraftLifecycleTests {
    @Test func sameSequenceNeedsTheSameSessionAndExactUtf8() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        var current = try await fixture.store.beginDraft(body: "が\0")
        current.title = "更新"
        try await fixture.store.updateDraft(current)
        let equivalent = Draft(id: current.id, target: current.target, baseRevision: current.baseRevision,
                               title: current.title, body: "か\u{3099}\0", sequence: current.sequence)
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.keepDraft(equivalent) }
        try await fixture.store.updateDraft(equivalent)
        #expect(try await fixture.store.draft(current.id).body.utf8.elementsEqual(current.body.utf8))
        let foreign = Draft(id: current.id, target: .snippet(UUID()), baseRevision: current.baseRevision,
                            title: current.title, body: "別session", sequence: current.sequence + 1)
        try await fixture.store.updateDraft(foreign)
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.discardDraft(foreign) }
        try await fixture.store.keepDraft(current)
        #expect(try await fixture.store.draft(current.id).body.utf8.elementsEqual(current.body.utf8))
    }

    @Test func aStaleTerminalOperationCannotRemoveNewerInput() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "保存済み")
        var old = try await fixture.store.editingDraft(for: id)
        old.body = "古い入力"
        var new = old
        new.body = "新しい入力"
        try await fixture.store.updateDraft(new)
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.save(old) }
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.keepDraft(old) }
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.discardDraft(old) }
        let recovered = try await fixture.store.save(old, mode: .saveAsNew)
        #expect(recovered != id)
        #expect(try await fixture.store.savedBody(id) == "保存済み")
        #expect(try await fixture.store.savedBody(recovered) == "古い入力")
        #expect(try await fixture.store.draft(old.id).body == "新しい入力")
    }

    @Test func committedFinishPreventsLateAutosaveResurrection() async throws {
        for save in [false, true] {
            let fixture = try TestDatabase()
            defer { fixture.removeFiles() }
            var input = try await fixture.store.beginDraft(body: "入力")
            input.body += "確定"
            if save { try await fixture.store.save(input) }
            else { try await fixture.store.discardDraft(input) }
            input.body += "遅延"
            try await fixture.store.updateDraft(input)
            #expect(try await fixture.store.drafts().isEmpty)
            await #expect(throws: StoreError.missing) { try await fixture.store.keepDraft(input) }
            #expect(try await fixture.store.search().count == (save ? 1 : 0))
        }
    }

    @Test func concurrentResumeReturnsOneSessionAndRevisionConflictPreservesBothInputs() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let second = SnippetStore(location: fixture.url)
        let id = try await create(fixture.store, body: "元の本文")
        async let firstResume = fixture.store.editingDraft(for: id)
        async let nextResume = second.editingDraft(for: id)
        let (first, next) = try await (firstResume, nextResume)
        #expect(first.id == next.id)
        var separate = try await second.beginDraft(target: .snippet(id))
        separate.body = "別の編集"
        try await second.updateDraft(separate)
        var winning = first
        winning.body = "確定した編集"
        try await fixture.store.save(winning)
        await #expect(throws: StoreError.conflict) { try await second.save(separate) }
        #expect(try await second.draft(separate.id).body == "別の編集")
        #expect(try await second.savedBody(id) == "確定した編集")
    }

    @Test(arguments: [-1, Int.max])
    func invalidConstructedOrderKeepsInputWithoutClaimingReplacement(sequence: Int) {
        var input = Draft(id: UUID(), target: .new, baseRevision: 0, title: "旧タイトル", body: "旧本文", sequence: sequence)
        let before = input.checkpoint
        input.body = "現在の本文\0か\u{3099}"
        input.title = "現在のタイトル"
        #expect(!input.canPersistSequence)
        #expect(input.body.utf8.elementsEqual("現在の本文\0か\u{3099}".utf8))
        #expect(input.title == "現在のタイトル")
        #expect(!input.canAutosave(over: before))
        #expect(input.replacement(of: before, title: input.title, body: input.body) == .rejected)
    }

    @Test @MainActor func exhaustedInputOrderRejectsNormalWritesAndOffersLosslessSaveAsNew() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let persisted = try await fixture.store.beginDraft(body: "DBに残す下書き")
        let database = try SQLiteDatabase(url: fixture.url)
        try database.execute("UPDATE drafts SET sequence=? WHERE id=?", [.int(Int.max - 1), .text(persisted.id.uuidString)])
        let restored = try await fixture.store.draft(persisted.id)
        let editor = EditorModel(draft: restored, store: fixture.store)
        editor.body = "メモリ上の最新入力\0か\u{3099}"
        editor.title = "回復した項目"
        #expect(editor.draft.sequence == Int.max && !editor.draft.canPersistSequence)
        await editor.persist(editor.draft)
        #expect(editor.failure != nil && editor.phase == .editing)
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.keepDraft(editor.draft) }
        await #expect(throws: StoreError.staleDraft) { try await fixture.store.discardDraft(editor.draft) }
        #expect(!(await editor.finish(.save)))
        #expect(editor.failure?.canSaveAsNew == true && editor.phase == .editing)
        #expect(editor.body.utf8.elementsEqual("メモリ上の最新入力\0か\u{3099}".utf8))
        #expect(await editor.finish(.saveAsNew))
        let item = try #require(try await fixture.store.search().first)
        let saved = try await fixture.store.snippet(item.id)
        #expect(saved.body.utf8.elementsEqual("メモリ上の最新入力\0か\u{3099}".utf8))
        #expect(saved.title == "回復した項目")
        let original = try await fixture.store.draft(persisted.id)
        #expect(original.sequence == Int.max - 1 && original.body == "DBに残す下書き")
    }

    @Test @MainActor func failedExitLeavesOriginalInputEditableAndSuccessIsTerminal() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let input = try await fixture.store.beginDraft(body: " \r\n")
        let editor = EditorModel(draft: input, store: fixture.store)
        #expect(!(await editor.finish(.save)))
        #expect(editor.phase == .editing && editor.body.utf8.elementsEqual(input.body.utf8))
        #expect(editor.failure != nil)
        editor.body = "保存する本文"
        #expect(await editor.finish(.save))
        #expect(editor.phase == .finished)
        #expect(!(await editor.finish(.save)))
        #expect(try await fixture.store.search().count == 1)
        let unavailable = SnippetStore(location: { throw StoreError.unavailable })
        let remaining = EditorModel(draft: input, store: unavailable)
        #expect(!(await remaining.finish(.keep)))
        #expect(remaining.phase == .editing && remaining.body.utf8.elementsEqual(input.body.utf8))
    }
}
