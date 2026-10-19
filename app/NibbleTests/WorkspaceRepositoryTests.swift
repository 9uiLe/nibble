import Foundation
import SQLite3
import Testing
@testable import Nibble

@Suite("Workspace publication and recovery")
struct WorkspaceRepositoryTests {
    @Test func exactInputSurvivesCheckpointReopeningAndPublication() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let original = " \tか\u{3099}\r\n行\r次\n\0👩🏽‍💻  "
        var draft = try await fixture.repository.beginDraft(title: " 題名\0 ", body: original)
        try draft.update(title: draft.title, body: original + "追記", values: [:])
        _ = try await fixture.repository.checkpoint(draft)
        let reopened = try WorkspaceRepository(location: fixture.location)
        let resumed = try await reopened.draft(id: draft.id)
        #expect(resumed.body.utf8.elementsEqual((original + "追記").utf8))
        let card = try await reopened.publish(resumed)
        let saved = try await fixture.repository.card(id: card.id)
        #expect(saved.body.utf8.elementsEqual(resumed.body.utf8))
        #expect(saved.title.utf8.elementsEqual(" 題名\0 ".utf8))
        #expect(try await fixture.repository.drafts().isEmpty)
    }

    @Test func checkpointRejectsOlderOrDifferentInputAndNeverResurrectsDiscardedWork() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let second = try WorkspaceRepository(location: fixture.location)
        var older = try await fixture.repository.beginDraft(title: "", body: "初期")
        try older.update(title: "", body: "途中", values: [:])
        var newer = older
        try newer.update(title: "", body: "最新", values: [:])
        _ = try await fixture.repository.checkpoint(newer)
        await #expect(throws: WorkspaceError.staleCheckpoint) { try await second.checkpoint(older) }
        let collision = WorkDraft(id: newer.id, target: newer.target, body: "別入力", sequence: newer.sequence)
        await #expect(throws: WorkspaceError.staleCheckpoint) { try await second.checkpoint(collision) }
        #expect(try await second.draft(id: newer.id).body == "最新")
        try await second.discardDraft(id: newer.id, expectedSequence: newer.sequence)
        await #expect(throws: WorkspaceError.missingDraft) { try await fixture.repository.checkpoint(newer) }
        #expect(try await second.list(query: WorkspaceQuery()).total == 0)
    }

    @Test func canonicalEquivalentEditingStillAdvancesInputSequence() throws {
        var draft = WorkDraft(body: "が")
        try draft.update(title: "", body: "か\u{3099}", values: [:])
        #expect(draft.sequence == 1)
        #expect(draft.body.utf8.elementsEqual("か\u{3099}".utf8))
        try draft.update(title: "", body: draft.body, values: [:])
        #expect(draft.sequence == 1)
    }

    @Test func moreLocalEditsCannotOverwriteAnotherResumedSessionsCheckpoint() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let second = try WorkspaceRepository(location: fixture.location)
        let initial = try await fixture.repository.beginDraft(title: "", body: "開始")
        var first = initial
        var stale = try await second.draft(id: initial.id)
        try first.update(title: "", body: "別の画面で保持した入力\0", values: [:])
        try stale.update(title: "", body: "古い画面での変更1", values: [:])
        try stale.update(title: "", body: "古い画面での変更2", values: [:])
        _ = try await fixture.repository.checkpoint(first)
        #expect(stale.sequence > first.sequence)
        await #expect(throws: WorkspaceError.staleCheckpoint) { try await second.checkpoint(stale) }
        await #expect(throws: WorkspaceError.staleCheckpoint) { try await second.publish(stale) }
        var resumed = try await second.draft(id: initial.id)
        #expect(resumed.body.utf8.elementsEqual(first.body.utf8))
        try resumed.update(title: "", body: resumed.body + "再開", values: [:])
        let retained = try await second.checkpoint(resumed)
        #expect(retained.body.utf8.elementsEqual((first.body + "再開").utf8))
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 0)
    }

    @Test func conflictingPublishRetainsLatestWorkAndDoesNotReplaceSavedText() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "保存済み")
        let second = try WorkspaceRepository(location: fixture.location)
        var firstEdit = try await fixture.repository.editingDraft(cardID: card.id)
        var secondEdit = try await second.editingDraft(cardID: card.id)
        try firstEdit.update(title: "", body: "先に確定", values: [:])
        try secondEdit.update(title: "", body: "失わせない入力\0", values: [:])
        _ = try await fixture.repository.publish(firstEdit)
        await #expect(throws: WorkspaceError.conflict) { try await second.publish(secondEdit) }
        let resumed = try await fixture.repository.draft(id: secondEdit.id)
        #expect(resumed.body.utf8.elementsEqual(secondEdit.body.utf8))
        #expect(try await second.card(id: card.id).body == "先に確定")
    }

    @Test func twoRepositoriesCannotPublishCompetingVersions() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "原文")
        let second = try WorkspaceRepository(location: fixture.location)
        var firstEdit = try await fixture.repository.editingDraft(cardID: card.id)
        var secondEdit = try await second.editingDraft(cardID: card.id)
        try firstEdit.update(title: "", body: "一方", values: [:])
        try secondEdit.update(title: "", body: "他方", values: [:])
        let firstInput = firstEdit
        let secondInput = secondEdit
        let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    _ = try await fixture.repository.publish(firstInput)
                    return true
                } catch WorkspaceError.conflict {
                    return false
                }
            }
            group.addTask {
                do {
                    _ = try await second.publish(secondInput)
                    return true
                } catch WorkspaceError.conflict {
                    return false
                }
            }
            var count = 0
            for try await succeeded in group where succeeded { count += 1 }
            return count
        }
        #expect(successes == 1)
        #expect(try await second.card(id: card.id).version == card.version + 1)
        #expect(try await second.drafts().count == 1)
    }

    @Test func emptyPublicationKeepsWorkAndPublicationRetryCannotDuplicateCards() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        var draft = try await fixture.repository.beginDraft(title: "残す", body: " \r\n ")
        await #expect(throws: WorkspaceError.emptyBody) { try await fixture.repository.publish(draft) }
        #expect(try await fixture.repository.draft(id: draft.id).title == "残す")
        try draft.update(title: draft.title, body: "利用できる内容", values: [:])
        _ = try await fixture.repository.publish(draft)
        await #expect(throws: WorkspaceError.missingDraft) { try await fixture.repository.publish(draft) }
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
    }

    @Test func sqlitePublicationFailureRetainsCheckpointAndRetryPublishesOnce() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        var draft = try await fixture.repository.beginDraft(title: "", body: "最初")
        try draft.update(title: "用件", body: "障害時にも保持する入力\0", values: [:])
        try fixture.executeFailureSetup("""
        CREATE TRIGGER reject_publication BEFORE INSERT ON cards
        BEGIN SELECT RAISE(ABORT,'injected publication failure'); END
        """)
        await #expect(throws: WorkspaceError.storage(code: SQLITE_CONSTRAINT)) { try await fixture.repository.publish(draft) }
        let reopened = try WorkspaceRepository(location: fixture.location)
        let retained = try await reopened.draft(id: draft.id)
        #expect(retained.body.utf8.elementsEqual(draft.body.utf8))
        #expect(try await reopened.list(query: WorkspaceQuery()).total == 0)
        try fixture.executeFailureSetup("DROP TRIGGER reject_publication")
        _ = try await reopened.publish(retained)
        await #expect(throws: WorkspaceError.missingDraft) { try await reopened.publish(retained) }
        #expect(try await reopened.list(query: WorkspaceQuery()).total == 1)
    }

    @Test func preparationResumesValuesAndCreatesAnIndependentUnpinnedCard() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let originalBody = "e{{相手}}\r\n{{ 相手 }}/{{用件}}/{{ }}/{{未完\0"
        let card = try await fixture.create(title: "ひな型", body: originalBody, usesVariables: true)
        let pinned = try await fixture.repository.setPinned(true, cardID: card.id, expectedVersion: card.version)
        var draft = try await fixture.repository.preparationDraft(cardID: card.id)
        try draft.update(title: "山田さんへの依頼", body: draft.body, values: ["相手": "\u{301}山田", "用件": "日程の確認"])
        _ = try await fixture.repository.checkpoint(draft)
        let reopened = try WorkspaceRepository(location: fixture.location)
        let resumed = try await reopened.draft(id: draft.id)
        #expect(resumed.usesVariables)
        #expect(resumed.values["相手"] == "\u{301}山田")
        let completed = try await reopened.publish(resumed)
        #expect(completed.id != card.id)
        #expect(completed.title == "山田さんへの依頼")
        #expect(completed.originTitle == "ひな型")
        #expect(!completed.pinned)
        #expect(!completed.usesVariables)
        #expect(completed.body.utf8.elementsEqual("e\u{301}山田\r\n\u{301}山田/日程の確認/{{ }}/{{未完\0".utf8))
        let unchanged = try await reopened.card(id: card.id)
        #expect(unchanged.version == pinned.version)
        #expect(unchanged.usesVariables)
        #expect(unchanged.body.utf8.elementsEqual(originalBody.utf8))
    }

    @Test func cancelledPreparationPublishesNothingAndInvalidValuesStayRecoverable() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(title: "ひな型", body: "{{相手}}へ", usesVariables: true)
        var draft = try await fixture.repository.preparationDraft(cardID: card.id)
        try draft.update(title: "途中の用件", body: draft.body, values: ["相手": " \n"])
        await #expect(throws: WorkspaceError.missingValues(["相手"])) { try await fixture.repository.publish(draft) }
        #expect(try await fixture.repository.draft(id: draft.id).values["相手"] == " \n")
        try await fixture.repository.discardDraft(id: draft.id, expectedSequence: draft.sequence)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
        #expect(try await fixture.repository.card(id: card.id).body == "{{相手}}へ")
    }

    @Test func trashedCardsKeepBytesAndRequireCurrentVersionToRestore() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "消さない原文\0か\u{3099}", usesVariables: true)
        let pinned = try await fixture.repository.setPinned(true, cardID: card.id, expectedVersion: card.version)
        let trashed = try await fixture.repository.trash(cardID: card.id, expectedVersion: pinned.version)
        #expect(pinned.usesVariables && trashed.usesVariables)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 0)
        #expect(try await fixture.repository.list(query: WorkspaceQuery(trash: true)).cards.map(\.id) == [card.id])
        await #expect(throws: WorkspaceError.missingCard) { try await fixture.repository.revalidate(cardID: card.id, expectedVersion: trashed.version) }
        await #expect(throws: WorkspaceError.conflict) { try await fixture.repository.restore(cardID: card.id, expectedVersion: pinned.version) }
        let restored = try await fixture.repository.restore(cardID: card.id, expectedVersion: trashed.version)
        #expect(restored.pinned)
        #expect(restored.usesVariables)
        #expect(restored.body.utf8.elementsEqual(card.body.utf8))
        #expect(try await fixture.repository.list(query: WorkspaceQuery(trash: true)).total == 0)
    }

    @Test func readOnlyKeyboardListsOnlyPinnedFixedCardsAndRejectsChangedVersions() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let fixed = try await fixture.create(body: "確定した本文")
        let template = try await fixture.create(body: "{{相手}}へ", usesVariables: true)
        let pinned = try await fixture.repository.setPinned(true, cardID: fixed.id, expectedVersion: fixed.version)
        _ = try await fixture.repository.setPinned(true, cardID: template.id, expectedVersion: template.version)
        _ = try await fixture.create(body: "ピンなし")
        let reader = try WorkspaceRepository(location: fixture.location, readOnly: true)
        #expect(try await reader.keyboardSummaries(limit: 50).map(\.id) == [fixed.id])
        #expect(try await reader.revalidate(cardID: fixed.id, expectedVersion: pinned.version).body == fixed.body)
        await #expect(throws: WorkspaceError.readOnly) { try await reader.beginDraft(title: "", body: "書き込まない") }
        var editing = try await fixture.repository.editingDraft(cardID: fixed.id)
        try editing.update(title: "", body: "変更後", values: [:])
        _ = try await fixture.repository.publish(editing)
        await #expect(throws: WorkspaceError.conflict) { try await reader.revalidate(cardID: fixed.id, expectedVersion: pinned.version) }
    }

    @Test func readOnlyInitializationNeverCreatesAnAbsentDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-absent-\(UUID().uuidString)")
        let location = directory.appendingPathComponent("workspace.sqlite")
        #expect(throws: WorkspaceError.self) { try WorkspaceRepository(location: location, readOnly: true) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func literalTemplateSyntaxSurvivesStorageAndIsAvailableToTheReadOnlyKeyboard() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let body = "{{name}}\r\n{{ helper }}\0か\u{3099}👩🏽‍💻"
        let card = try await fixture.create(title: "コード例", body: body)
        #expect(!card.usesVariables)
        let pinned = try await fixture.repository.setPinned(true, cardID: card.id, expectedVersion: card.version)
        let reader = try WorkspaceRepository(location: fixture.location, readOnly: true)
        #expect(try await reader.keyboardSummaries(limit: 50).map(\.id) == [card.id])
        let current = try await reader.revalidate(cardID: card.id, expectedVersion: pinned.version)
        #expect(current.body.utf8.elementsEqual(body.utf8))
        #expect(!current.usesVariables)
        let editing = try await fixture.repository.editingDraft(cardID: card.id)
        #expect(try editing.renderedBody().utf8.elementsEqual(body.utf8))
    }

    @Test func choosingTemplateModeIsDurableAndDoesNotRewriteTheOriginal() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let body = "{{相手}}へ\r\n原文\0"
        var draft = try await fixture.repository.beginDraft(title: "用途", body: body)
        try draft.update(title: draft.title, body: body, values: [:], usesVariables: true)
        #expect(draft.sequence == 1)
        _ = try await fixture.repository.checkpoint(draft)
        let reopened = try WorkspaceRepository(location: fixture.location)
        let retained = try await reopened.draft(id: draft.id)
        #expect(retained.usesVariables)
        let conflictingChoice = WorkDraft(id: draft.id, target: draft.target, title: draft.title, body: body, sequence: draft.sequence)
        await #expect(throws: WorkspaceError.staleCheckpoint) { try await reopened.checkpoint(conflictingChoice) }
        let template = try await reopened.publish(retained)
        #expect(template.usesVariables)
        let pinned = try await reopened.setPinned(true, cardID: template.id, expectedVersion: template.version)
        #expect(pinned.usesVariables)
        let reader = try WorkspaceRepository(location: fixture.location, readOnly: true)
        #expect(try await reader.keyboardSummaries(limit: 50).isEmpty)
        var editing = try await reopened.editingDraft(cardID: template.id)
        #expect(editing.usesVariables)
        try editing.update(title: editing.title, body: editing.body, values: [:], usesVariables: false)
        _ = try await reopened.checkpoint(editing)
        let literalWork = try await fixture.repository.draft(id: editing.id)
        #expect(!literalWork.usesVariables)
        #expect(try literalWork.renderedBody().utf8.elementsEqual(body.utf8))
        let fixed = try await reopened.publish(literalWork)
        #expect(!fixed.usesVariables && fixed.pinned)
        #expect(fixed.body.utf8.elementsEqual(body.utf8))
        #expect(try await reader.keyboardSummaries(limit: 50).map(\.id) == [fixed.id])
    }

    @Test func unsupportedSchemaIsRejectedWithoutReplacingStoredText() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "保持する{{literal}}\0")
        try fixture.executeFailureSetup("PRAGMA user_version=1")
        #expect(throws: WorkspaceError.unsupportedSchema) { try WorkspaceRepository(location: fixture.location) }
        #expect(throws: WorkspaceError.unsupportedSchema) { try WorkspaceRepository(location: fixture.location, readOnly: true) }
        try fixture.executeFailureSetup("PRAGMA user_version=2")
        #expect(try await fixture.repository.card(id: card.id).body.utf8.elementsEqual(card.body.utf8))
    }

    @Test func fiveThousandCardsStayPagedAndSearchOnlyNormalizesLookup() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.removeFiles() }
        var sentinel: UUID?
        for index in 0..<5_000 {
            let body = index == 4_321 ? "東京都 ＡＢＣ カナ か\u{3099} %_\\\0終" : "定型文 \(index)"
            let card = try await fixture.create(title: "番号\(index)", body: body)
            if index == 4_321 { sentinel = card.id }
        }
        let first = try await fixture.repository.list(query: WorkspaceQuery())
        #expect(first.total == 5_000 && first.cards.count == 50 && first.hasMore)
        let last = try await fixture.repository.list(query: WorkspaceQuery(offset: 4_950))
        #expect(last.cards.count == 50 && !last.hasMore)
        #expect(Set(first.cards.map(\.id)).isDisjoint(with: Set(last.cards.map(\.id))))
        let expected = try #require(sentinel)
        for query in ["東京都", "abc", "ｶﾅ", "が", "%_\\", "\0終"] {
            #expect(try await fixture.repository.list(query: WorkspaceQuery(query: query)).cards.map(\.id) == [expected])
        }
        #expect(try await fixture.repository.list(query: WorkspaceQuery(query: "かな")).cards.isEmpty)
        #expect(try await fixture.repository.list(query: WorkspaceQuery(query: "か")).cards.isEmpty)
        #expect(try await fixture.repository.card(id: expected).body.contains("か\u{3099}"))
    }

    @Test func templateKeepsAllLiteralBytesAndReportsBlankOrMissingValues() throws {
        let source = "{{相手}}/{{ 相手 }}/{{用件}}/{{ }}/{{改\n行}}/{{未完\0"
        let template = TextTemplate(source)
        #expect(template.names == ["相手", "用件"])
        #expect(throws: WorkspaceError.missingValues(["用件"])) { try template.render(values: ["相手": "山田"]) }
        #expect(throws: WorkspaceError.missingValues(["相手"])) { try template.render(values: ["相手": " \r\n", "用件": "依頼"]) }
        let rendered = try template.render(values: ["相手": "山田", "用件": "依頼"])
        #expect(rendered.utf8.elementsEqual("山田/山田/依頼/{{ }}/{{改\n行}}/{{未完\0".utf8))
        #expect(template.body.utf8.elementsEqual(source.utf8))
        for (prefix, value) in [("e", "\u{301}"), ("👩", "\u{200D}💻"), ("\r", "\n次")] {
            let body = prefix + "{{境界}}末"
            #expect(try TextTemplate(body).render(values: ["境界": value]).utf8.elementsEqual((prefix + value + "末").utf8))
        }
    }
}

private struct WorkspaceFixture: Sendable {
    let directory: URL
    let location: URL
    let repository: WorkspaceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-tests-\(UUID().uuidString)", isDirectory: true)
        location = directory.appendingPathComponent("workspace.sqlite")
        repository = try WorkspaceRepository(location: location)
    }

    func create(title: String = "", body: String, usesVariables: Bool = false) async throws -> TextCard {
        var draft = try await repository.beginDraft(title: title, body: body)
        try draft.update(title: title, body: body, values: [:], usesVariables: usesVariables)
        return try await repository.publish(draft)
    }

    func executeFailureSetup(_ sql: String) throws {
        var candidate: OpaquePointer?
        let status = sqlite3_open_v2(location.path, &candidate, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database = candidate else {
            sqlite3_close_v2(candidate)
            throw WorkspaceError.storage(code: status)
        }
        defer { sqlite3_close_v2(database) }
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw WorkspaceError.storage(code: result) }
    }

    func removeFiles() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Could not remove workspace fixture: \(error)")
        }
    }
}
