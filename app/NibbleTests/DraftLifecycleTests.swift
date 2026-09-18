import Foundation
import Testing
@testable import Nibble

@Suite("Draft snapshots and recovery")
struct DraftLifecycleTests {
    @Test func byteComparisonPreservesEmptyNullUnicodeAndLongInput() {
        #expect(SnippetText.hasSameBytes("", ""))
        #expect(!SnippetText.hasSameBytes("", "a"))
        #expect(SnippetText.hasSameBytes("a\0b", "a\0b"))
        #expect(!SnippetText.hasSameBytes("a\0b", "a\0c"))
        #expect(!SnippetText.hasSameBytes("が", "か\u{3099}"))
        #expect(SnippetText.hasSameBytes("👩🏽‍💻\n", "👩🏽‍💻\n"))
        let prefix = String(repeating: "a", count: 999_999)
        #expect(SnippetText.hasSameBytes(prefix + "x", prefix + "x"))
        #expect(!SnippetText.hasSameBytes(prefix + "x", prefix + "y"))
        var draft = Draft(id: UUID(), snippetID: nil, baseRevision: 0, title: "", body: prefix + "x")
        draft.body = prefix + "x"
        #expect(draft.sequence == 0)
        draft.body = prefix + "y"
        #expect(draft.sequence == 1)
    }

    @Test func staleSaveCannotOverwriteNewerAutosave() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let id = try await create(store, body: "保存済み")
        var stale = try await store.beginDraft(snippetID: id)
        stale.body = "古い入力"
        var newest = stale
        newest.body = "最新の入力"
        try await store.updateDraft(newest)

        await #expect(throws: StoreError.staleDraft) { try await store.save(stale) }
        #expect(try await store.snippet(id).body == "保存済み")
        #expect(try await store.draft(stale.id).body == newest.body)

        let recovered = try await store.save(stale, asNew: true)
        #expect(recovered != id)
        #expect(try await store.snippet(recovered).body == stale.body)
        #expect(try await store.draft(stale.id).body == newest.body)
    }

    @Test func closingOrDiscardingAStaleSnapshotPreservesNewerInput() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let stale = try await store.beginDraft()
        var newest = stale
        newest.body = "ほかの編集画面の入力"
        try await store.updateDraft(newest)
        await #expect(throws: StoreError.staleDraft) { try await store.keepDraft(stale) }
        await #expect(throws: StoreError.staleDraft) { try await store.discardDraft(stale) }
        #expect(try await store.draft(stale.id).body == newest.body)
    }

    @Test func equalSequenceWithDifferentUnicodeBytesIsAConflict() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let initial = try await store.beginDraft()
        var first = initial
        var second = initial
        first.body = "が"
        second.body = "か\u{3099}"
        #expect(first.body == second.body) // Canonical equality is insufficient for the raw-text contract.
        #expect(first.sequence == second.sequence)
        try await store.updateDraft(first)
        await #expect(throws: StoreError.staleDraft) { try await store.save(second) }
        #expect(try await store.draft(first.id).body.utf8.elementsEqual(first.body.utf8))
    }

    @Test func inputSequenceChangesOnlyWhenBytesChange() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        var draft = try await database.store.beginDraft(body: "が")
        draft.body = "が"
        draft.title = ""
        #expect(draft.sequence == 0)
        draft.body = "か\u{3099}"
        #expect(draft.sequence == 1)
        draft.title = "見出し"
        #expect(draft.sequence == 2)
    }

    @Test func concurrentResumeUsesOnePersistedDraft() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let first = database.store
        let second = SnippetStore(location: database.url)
        let id = try await create(first, body: "本文")
        async let a = first.editingDraft(for: id)
        async let b = second.editingDraft(for: id)
        let (left, right) = try await (a, b)
        #expect(left.id == right.id)
        #expect(try await first.drafts().map(\.id) == [left.id])
    }

    @Test func libraryReturnsBoundedSummariesAndReopensTheFullBody() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let text = String(repeating: "長文\n", count: 100_000)
        var draft = try await store.beginDraft(body: text)
        draft.title = String(repeating: "題", count: 1_000)
        try await store.updateDraft(draft)
        let page = try await store.library(LibraryRequest())
        #expect(page.drafts.count == 1)
        #expect(page.drafts.first?.title.count == 180)
        #expect(page.drafts.first?.preview.count == 180)
        #expect(try await store.draft(draft.id).body.utf8.elementsEqual(text.utf8))
        #expect(try await store.draft(draft.id).title == draft.title)
    }

    @Test func untitledDraftsRemainDistinctAndAllLibraryBoundsTheirRows() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let saved = try await create(store, body: "保存済みの本文")
        var ids: [UUID] = []
        for number in 0..<20 {
            let draft = try await store.beginDraft(body: "未完了の本文 \(number)\n" + String(repeating: "長", count: 1_000))
            ids.append(draft.id)
        }
        let all = try await store.library(LibraryRequest())
        #expect(all.items.map(\.id) == [saved])
        #expect(all.drafts.count == 3 && all.hasMoreDrafts)
        let first = try await store.library(LibraryRequest(filter: .drafts, limit: 2))
        #expect(first.drafts.count == 2 && first.hasMore)
        let expanded = try await store.library(LibraryRequest(filter: .drafts, limit: 2).expanded)
        #expect(expanded.drafts.count == 20 && !expanded.hasMore)
        #expect(Set(expanded.drafts.map(\.id)) == Set(ids))
        #expect(Set(expanded.drafts.map(\.displayTitle)).count == 20)
        #expect(expanded.drafts.allSatisfy { $0.preview.count == 180 && $0.updatedAt.timeIntervalSince1970 > 0 })
        #expect(Array(expanded.drafts.prefix(3)) == all.drafts)
        let chosen = try #require(expanded.drafts.first)
        #expect(try await store.draft(chosen.id).body.count > chosen.preview.count)
    }

    @Test func pageLookaheadAndFiltersStayConsistent() async throws {
        let database = try TestDatabase()
        defer { database.removeFiles() }
        let store = database.store
        let first = try await create(store, body: "first")
        _ = try await create(store, body: "second")
        let page = try await store.library(LibraryRequest(limit: 1))
        #expect(page.items.count == 1)
        #expect(page.hasMore)
        try await store.setPinned(true, id: first)
        let pinned = try await store.library(LibraryRequest(filter: .pinned, limit: 1))
        #expect(pinned.items.map(\.id) == [first])
        #expect(!pinned.hasMore)
        let missing = try await store.library(LibraryRequest(query: "なし", limit: 1))
        #expect(missing.items.isEmpty)
        #expect(!missing.hasMore)
    }
}

extension UIIntegrationTests {
    @Suite("Fresh editor sessions")
    @MainActor
    struct EditorSessionTests {
        @Test(arguments: [false, true])
        func openingReadsTheLatestDraft(resumeByID: Bool) async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let id = try await create(store, body: "保存済み")
            var draft = try await store.beginDraft(snippetID: id)
            let library = LibraryModel(store: store)
            await library.refresh()
            // Simulate an extension write after the library obtained its rows.
            draft.body = "一覧取得後の最新入力"
            let extensionStore = SnippetStore(location: database.url)
            try await extensionStore.updateDraft(draft)
            await library.open(resumeByID ? .draft(draft.id) : .snippet(id))
            #expect(library.editor?.id == draft.id)
            #expect(library.editor?.body == draft.body)
            #expect(library.failure == nil)
        }

        @Test func removedDraftCannotBeReopenedFromAnOldRow() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let draft = try await store.beginDraft(body: "削除する下書き")
            let library = LibraryModel(store: store)
            await library.refresh()
            try await store.discardDraft(draft)
            await library.open(.draft(draft.id))
            #expect(library.editor == nil)
            #expect(library.failure != nil)
            #expect(try await store.drafts().isEmpty)
        }

        @Test func deletedSnippetCannotBeOpenedThroughACachedDraft() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let store = database.store
            let id = try await create(store, body: "削除する項目")
            _ = try await store.beginDraft(snippetID: id)
            let library = LibraryModel(store: store)
            await library.refresh()
            try await store.setDeleted(true, id: id)
            await library.open(.snippet(id))
            #expect(library.editor == nil)
            #expect(library.failure != nil)
        }

        @Test func aFailedFinishRemainsEditableAndSuccessfulFinishIsTerminal() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let editor = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            #expect(!(await editor.finish(.save)))
            #expect(editor.phase == .editing)
            #expect(editor.failure?.canSaveAsNew == false)
            editor.body = "保存する本文"
            #expect(await editor.finish(.save))
            #expect(editor.phase == .finished)
            #expect(editor.failure == nil)
            editor.body = "終了後の入力"
            #expect(editor.body == "保存する本文")
            #expect(!(await editor.finish(.save)))
            #expect(try await database.store.search().count == 1)
        }

        @Test func aMissingDraftDoesNotReportSuccessfulClose() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let draft = try await database.store.beginDraft(body: "保持する入力")
            let editor = EditorModel(draft: draft, store: database.store)
            try await database.store.discardDraft(draft)
            #expect(!(await editor.finish(.keep)))
            #expect(editor.phase == .editing)
            #expect(editor.body == draft.body)
            #expect(editor.failure?.canSaveAsNew == true)
            #expect(await editor.finish(.saveAsNew))
            let saved = try #require(try await database.store.search().first)
            #expect(try await database.store.snippet(saved.id).body == draft.body)
        }

        @Test func changingSearchCriteriaResetsPaginationWithoutViewCallbacks() throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let library = LibraryModel(store: database.store)
            library.showMore()
            #expect(library.request.limit == 200)
            library.filter = .all
            library.query = ""
            #expect(library.request.limit == 200)
            library.query = "検索|語"
            #expect(library.request.limit == 100)
            #expect(library.request.query == "検索|語")
            library.showMore()
            library.filter = .pinned
            #expect(library.request.limit == 100)
            #expect(library.request.filter == .pinned)
            #expect(library.query == "検索|語")
        }
    }
}
