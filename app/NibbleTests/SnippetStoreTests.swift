import Foundation
import Testing
@testable import Nibble

@Suite("Saved text contracts")
struct SnippetStoreTests {
    @Test func originalBytesSurviveEditingAndASecondConnection() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let source = " \tか\u{3099}\r\n行\r次\n\0👩🏽‍💻  "
        let id = try await create(fixture.store, title: " 題名\0 ", body: source)
        let reopened = SnippetStore(location: fixture.url)
        let saved = try await reopened.snippet(id)
        #expect(saved.body.utf8.elementsEqual(source.utf8))
        #expect(saved.title.utf8.elementsEqual(" 題名\0 ".utf8))
        var editing = try await reopened.editingDraft(for: id)
        editing.body += "追記"
        try await reopened.save(editing)
        #expect(try await fixture.store.savedBody(id).utf8.elementsEqual((source + "追記").utf8))
    }

    @Test func searchNormalizesOnlyItsLookupAndTreatsMetacharactersLiterally() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, title: "題", body: "東京都 ＡＢＣ カナ か\u{3099} %_\\")
        _ = try await create(fixture.store, body: "大阪 かな")
        for query in ["東", "題", "abc", "ｶﾅ", "が", "%_\\"] {
            #expect(try await fixture.store.search(query).map(\.id) == [id])
        }
        #expect(try await fixture.store.search("かな").map(\.id) != [id])
        #expect(try await !fixture.store.search("か").contains { $0.id == id })
        #expect(try await fixture.store.savedBody(id).contains("か\u{3099}"))
    }

    @Test func countsAreIndependentOfSearchAndDraftsHaveTheirOwnBudget() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let first = try await create(fixture.store, body: "一致")
        _ = try await create(fixture.store, body: "別の本文")
        try await fixture.store.setPinned(true, id: first)
        for index in 0..<3 { _ = try await fixture.store.beginDraft(body: "下書き \(index)") }
        let pages = try await fixture.store.libraries([
            LibraryRequest(limit: 1), LibraryRequest(query: "一致"), LibraryRequest(filter: .drafts, limit: 2)
        ])
        #expect(pages.count == 3)
        #expect(pages.allSatisfy { $0.counts == LibraryCounts(saved: 2, pinned: 1, drafts: 3) })
        #expect(pages[0].items.count == 1 && pages[0].hasMore && pages[0].drafts.count == 1 && pages[0].hasMoreDrafts)
        #expect(pages[1].items.map(\.id) == [first] && pages[1].drafts.isEmpty)
        #expect(pages[2].items.isEmpty && pages[2].drafts.count == 2 && pages[2].hasMore)
    }

    @Test func trashRequiresTheExpectedStateAndPermanentDeletionIncludesDrafts() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        let id = try await create(fixture.store, body: "残す本文")
        let editing = try await fixture.store.editingDraft(for: id)
        await #expect(throws: StoreError.missing) { try await fixture.store.mutate(.restore, id: id) }
        try await fixture.store.setPinned(true, id: id)
        try await fixture.store.mutate(.delete, id: id)
        await #expect(throws: StoreError.missing) { try await fixture.store.savedBody(id) }
        await #expect(throws: StoreError.missing) { try await fixture.store.mutate(.delete, id: id) }
        let reopened = SnippetStore(location: fixture.url)
        #expect(try await reopened.search(filter: .trash).map(\.id) == [id])
        try await reopened.mutate(.restore, id: id)
        #expect(try await fixture.store.snippet(id).pinned)
        #expect(try await fixture.store.savedBody(id) == "残す本文")
        await #expect(throws: StoreError.missing) { try await fixture.store.mutate(.permanentlyDelete, id: id) }
        try await reopened.mutate(.delete, id: id)
        try await reopened.mutate(.permanentlyDelete, id: id)
        await #expect(throws: StoreError.missing) { try await fixture.store.snippet(id) }
        await #expect(throws: StoreError.missing) { try await fixture.store.draft(editing.id) }
    }

    @Test func byteLimitsAndFreeFeaturesDoNotDiscardExistingInput() async throws {
        let fixture = try TestDatabase()
        defer { fixture.removeFiles() }
        var input = try await fixture.store.beginDraft(body: String(repeating: "あ", count: 333_333) + "x")
        input.title = String(repeating: "あ", count: 170) + "xy"
        let id = try await fixture.store.save(input)
        var changed = try await fixture.store.editingDraft(for: id)
        changed.body += "x"
        try await fixture.store.updateDraft(changed)
        await #expect(throws: StoreError.tooLarge) { try await fixture.store.save(changed) }
        #expect(try await fixture.store.savedBody(id).utf8.count == 1_000_000)
        #expect(try await fixture.store.draft(changed.id).body.utf8.count == 1_000_001)
        changed.body = "入力を保持"
        changed.title += "z"
        await #expect(throws: StoreError.tooLarge) { try await fixture.store.save(changed) }
        changed.title = "題名"
        changed.body = " \r\n "
        try await fixture.store.updateDraft(changed)
        await #expect(throws: StoreError.empty) { try await fixture.store.save(changed) }
        #expect(try await fixture.store.draft(changed.id).body.utf8.elementsEqual(changed.body.utf8))
        #expect(try await fixture.store.savedBody(id).utf8.count == 1_000_000)
        #expect(FeatureAccess.availability(.variableReplacement, pro: false).isAvailable)
        #expect(!FeatureAccess.subscriptionsOffered)
    }

    @Test func variableExpansionChangesOnlyConfirmedOutputAndHandlesGraphemeBoundaries() throws {
        let source = "{{ 宛名 }}\r\n{{宛名}}/{{未入力}}/{{ }}/{{未完"
        let template = SnippetVariables(source)
        #expect(template.names == [testVariableName("宛名"), testVariableName("未入力")])
        #expect(template.filled(with: testVariableValues(["宛名": "山田"])) == nil)
        #expect(template.filled(with: testVariableValues(["宛名": "山田", "未入力": ""])) == nil)
        let output = try #require(template.filled(with: testVariableValues(["宛名": "山田", "未入力": "値"])))
        #expect(output == "山田\r\n山田/値/{{ }}/{{未完")
        #expect(template.body.utf8.elementsEqual(source.utf8))
        for (body, value) in [("e{{境界}}末", "\u{301}"), ("👩{{境界}}末", "\u{200D}💻"), ("\r{{境界}}末", "\n")] {
            let parsed = SnippetVariables(body)
            let values = testVariableValues(["境界": value])
            let complete = try #require(parsed.filled(with: values))
            for count in 0...3 {
                let preview = try #require(parsed.filledPrefix(with: values, characterLimit: count))
                #expect(preview.text == String(complete.prefix(count)))
                #expect(preview.hasMore == (complete.count > count))
            }
        }
        #expect(VariableName.issue("改\n行") == .unsupportedCharacter)
        #expect(VariableName.issue(String(repeating: "長", count: 41)) == .tooLong)
    }
}
