import Foundation
import Testing
@testable import Nibble

@Suite("Prompt creation, body editing, rename and undo")
@MainActor
struct PromptFlowTests {
    @Test func creationRequiresBothFieldsAndKeepsTheExactInputAfterRejection() async throws {
        let fixture = try PromptFixture()
        defer { fixture.removeFiles() }
        let draft = try await fixture.storage.beginDraft(title: "", body: "")
        let editor = DraftSessionModel(draft: draft, storage: fixture.storage, contentKind: .prompt)
        editor.update(title: " \n", body: " \tか\u{3099}\r\n👩🏽‍💻 {{literal}}  ")
        #expect(!editor.canSavePrompt)
        #expect(await editor.save() == nil && editor.error == .emptyTitle)
        #expect(try await fixture.storage.list(query: WorkspaceQuery()).total == 0)
        let original = editor.draft.body
        editor.update(title: "  用途  ", body: " \t\n")
        #expect(await editor.save() == nil && editor.error == .emptyBody)
        editor.update(body: original)
        #expect(editor.canSavePrompt)
        let saved = try #require(await editor.save())
        let durable = try await fixture.storage.card(id: saved.id)
        #expect(durable.title.utf8.elementsEqual("  用途  ".utf8))
        #expect(durable.body.utf8.elementsEqual(original.utf8))
    }

    @Test(arguments: ["元の用途", ""]) func bodyEditingReturnsToTheSamePromptAndDoesNotChangeItsTitle(title: String) async throws {
        let fixture = try PromptFixture()
        defer { fixture.removeFiles() }
        let original = try await fixture.create(title: title)
        let detail = PromptSessionModel(card: original, storage: fixture.storage)
        await detail.beginEditing()
        let editor = try #require(detail.editor)
        #expect(!editor.hasChanges && !editor.canSavePrompt)
        let replacement = " \t変更後\r\nか\u{3099} 👩🏽‍💻  "
        editor.update(body: replacement)
        #expect(editor.hasChanges && editor.canSavePrompt)
        let saved = try #require(await editor.save())
        await detail.finishedEditing(saved: true)
        #expect(detail.editor == nil && detail.card.id == original.id)
        #expect(detail.card.title.utf8.elementsEqual(original.title.utf8))
        #expect(detail.card.body.utf8.elementsEqual(replacement.utf8))
        #expect(saved.id == original.id && saved.version == original.version + 1)
    }

    @Test func discardingChangedInputLeavesTheSavedPromptUntouchedAndRemovesOnlyItsDraft() async throws {
        let fixture = try PromptFixture()
        defer { fixture.removeFiles() }
        let original = try await fixture.create()
        let detail = PromptSessionModel(card: original, storage: fixture.storage)
        await detail.beginEditing()
        let editor = try #require(detail.editor)
        editor.update(body: "破棄する変更")
        #expect(await editor.checkpoint())
        #expect(await editor.discard())
        await detail.finishedEditing(saved: false)
        #expect(detail.card == original && detail.editor == nil)
        #expect(try await fixture.storage.card(id: original.id) == original)
        #expect(try await fixture.storage.drafts().isEmpty)
    }

    @Test func renameOnlyChangesTheTitleAndRefusesStaleConfirmation() async throws {
        let fixture = try PromptFixture()
        defer { fixture.removeFiles() }
        let original = try await fixture.create()
        let first = PromptSessionModel(card: original, storage: fixture.storage)
        let stale = PromptSessionModel(card: original, storage: fixture.storage)
        first.renameTitle = "  新しい用途\u{3099}  "
        #expect(await first.rename())
        #expect(first.card.body.utf8.elementsEqual(original.body.utf8))
        #expect(first.card.id == original.id && first.card.version == original.version + 1)
        stale.renameTitle = "残すべき失敗入力"
        #expect(!(await stale.rename()))
        #expect(stale.error == .conflict && stale.renameTitle == "残すべき失敗入力")
        #expect(try await fixture.storage.card(id: original.id).title == first.renameTitle)
        first.renameTitle = " \n"
        #expect(!(await first.rename()) && first.error == .emptyTitle)
        #expect(try await fixture.storage.drafts().isEmpty)
    }

    @Test func deletionUndoRestoresTheSameIdentityAndExactBody() async throws {
        let fixture = try PromptFixture()
        defer { fixture.removeFiles() }
        let original = try await fixture.create()
        let detail = PromptSessionModel(card: original, storage: fixture.storage)
        let deleted = try #require(await detail.trash())
        let home = WorkspaceModel(storage: fixture.storage)
        await home.finishedDeletingPrompt(deleted)
        #expect(home.cards.isEmpty && home.route == nil)
        await home.restore(deleted)
        let restored = try #require(home.cards.first)
        #expect(restored.id == original.id && restored.deletedAt == nil)
        #expect(restored.body.utf8.elementsEqual(original.body.utf8))
        #expect(restored.title.utf8.elementsEqual(original.title.utf8))
    }
}

private struct PromptFixture {
    let directory: URL
    let storage: WorkspaceRepository
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-flow-" + UUID().uuidString)
        storage = try WorkspaceRepository(location: directory.appendingPathComponent("workspace.sqlite"))
    }
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
    func create(title: String = "元の用途") async throws -> TextCard {
        let draft = try await storage.beginDraft(title: title, body: " \t原文\r\nか\u{3099}👩🏽‍💻 {{literal}}  ")
        let saved = try await storage.publish(draft)
        return try await storage.card(id: saved.id)
    }
}
