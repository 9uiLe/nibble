import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

@Suite("Workspace sessions reach durable and external results")
@MainActor
struct WorkspaceSessionTests {
    @Test func awaitingSaveMakesTheExactEditedInputDurable() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let draft = try await fixture.repository.beginDraft(title: "", body: "開始")
        let model = DraftSessionModel(draft: draft, storage: fixture.repository)
        let original = " \tか\u{3099}\r\n👩🏽‍💻\0原文  "
        model.update(title: "用途\0", body: original)
        let saved = try #require(await model.save())
        let reopened = try WorkspaceRepository(location: fixture.location)
        let card = try await reopened.card(id: saved.id)
        #expect(card.body.utf8.elementsEqual(original.utf8))
        #expect(card.title.utf8.elementsEqual("用途\0".utf8))
        #expect(try await reopened.drafts().isEmpty)
        #expect(model.hasCheckpoint && !model.busy && model.error == nil)
    }

    @Test func closingAWorkSessionAllowsReopeningAndSavingItsLatestInput() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let draft = try await fixture.repository.beginDraft(title: "", body: "")
        let first = DraftSessionModel(draft: draft, storage: fixture.repository)
        first.update(title: "途中の用件", body: "日本語の訂正後\n\0")
        #expect(await first.suspend())
        let reopened = try WorkspaceRepository(location: fixture.location)
        let retained = try await reopened.draft(id: draft.id)
        let resumed = DraftSessionModel(draft: retained, storage: reopened)
        #expect(resumed.draft.body.utf8.elementsEqual(first.draft.body.utf8))
        resumed.update(body: resumed.draft.body + "再開して完成")
        let saved = try #require(await resumed.save())
        #expect(try await fixture.repository.card(id: saved.id).body.utf8.elementsEqual("日本語の訂正後\n\0再開して完成".utf8))
    }

    @Test func checkpointSuccessCannotMeanOnlyAnOlderSnapshotWasRetained() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let initial = try await fixture.repository.beginDraft(title: "", body: "最初")
        let model = DraftSessionModel(draft: initial, storage: storage)
        model.update(body: "保持中の入力")
        let gate = SessionOperationGate()
        await storage.pauseNextCheckpoint(at: gate)
        async let checkpointed = model.checkpoint()
        await gate.waitUntilEntered()
        model.update(body: "保持中に届いた最新入力\0")
        async let overlapping = model.checkpoint()
        await gate.release()
        let mayClose = await checkpointed
        let overlapMayClose = await overlapping
        let retained = try await fixture.repository.draft(id: initial.id)
        #expect(mayClose && overlapMayClose && model.hasCheckpoint && model.error == nil)
        #expect(retained.body.utf8.elementsEqual(model.draft.body.utf8))
    }

    @Test func resumedEditorConflictRetainsBothInputsAndRescueRetryUsesOneDraft() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let initial = try await fixture.repository.beginDraft(title: "", body: "開始")
        let first = DraftSessionModel(draft: initial, storage: fixture.repository)
        let storage = SessionStorageProbe(base: fixture.repository)
        let second = DraftSessionModel(draft: initial, storage: storage)
        first.update(body: "先に保持した入力\0")
        #expect(await first.suspend())
        second.update(body: "古い画面の変更1")
        second.update(body: "救出する{{原文}}\0", usesVariables: true)
        #expect(!(await second.suspend()))
        #expect(second.error == .staleCheckpoint && !second.hasCheckpoint)
        #expect(try await fixture.repository.draft(id: initial.id).body == "先に保持した入力\0")
        await storage.failNextPublish(with: .storage(code: 10))
        #expect(await second.saveAsNew() == nil)
        #expect(second.error == .storage(code: 10) && second.hasIndependentRecovery)
        let failedWork = try await fixture.repository.drafts()
        let rescueID = try #require(failedWork.first(where: { $0.id != initial.id })?.id)
        #expect(failedWork.count == 2)
        second.update(body: "救出前に訂正した{{原文}}\0")
        await storage.failNextPublish(with: .storage(code: 13))
        #expect(await second.saveAsNew() == nil)
        #expect(second.error == .storage(code: 13) && second.hasIndependentRecovery)
        #expect(Set(try await fixture.repository.drafts().map(\.id)) == [initial.id, rescueID])
        let saved = try #require(await second.saveAsNew())
        #expect(saved.body.utf8.elementsEqual(second.draft.body.utf8) && saved.usesVariables)
        #expect(second.error == nil && !second.hasIndependentRecovery)
        #expect(try await fixture.repository.drafts().map(\.id) == [initial.id])
        #expect(try await fixture.repository.draft(id: initial.id).body == "先に保持した入力\0")
        #expect(await second.saveAsNew()?.id == saved.id)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
    }

    @Test func suspendOwnsInputUntilTheLastCheckpointCompletes() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let initial = try await fixture.repository.beginDraft(title: "", body: "閉じる内容")
        let model = DraftSessionModel(draft: initial, storage: storage)
        model.update(title: "用件")
        let gate = SessionOperationGate()
        await storage.pauseNextCheckpoint(at: gate)
        async let closed = model.suspend()
        await gate.waitUntilEntered()
        #expect(model.busy)
        model.update(body: "閉じる処理中の遅れた入力")
        #expect(model.draft.body == "閉じる内容")
        await gate.release()
        let didClose = await closed
        #expect(didClose)
        #expect(!model.busy)
        #expect(try await fixture.repository.draft(id: initial.id).body == "閉じる内容")
    }

    @Test(arguments: [false, true])
    func supersededEditorCanDiscardOnlyItsLocalInputWithoutSavingAnotherCard(workEnded: Bool) async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let created = try await fixture.create(body: "保存済みの原文\0")
        let original = try await fixture.repository.card(id: created.id)
        let initial = try await fixture.repository.editingDraft(cardID: original.id)
        let local = DraftSessionModel(draft: initial, storage: fixture.repository)
        local.update(body: "破棄を選ぶこの画面の入力")
        var other = initial
        try other.update(title: "", body: "別の画面で保持した入力\0", values: [:])
        let expectedCard: TextCard
        if workEnded {
            _ = try await fixture.repository.publish(other)
            expectedCard = try await fixture.repository.card(id: original.id)
        } else {
            _ = try await fixture.repository.checkpoint(other)
            expectedCard = original
        }
        #expect(!(await local.suspend()))
        #expect(local.discardsLocalInputOnly)
        #expect(local.error == (workEnded ? .missingDraft : .staleCheckpoint))
        #expect(await local.discard())
        let retainedCard = try await fixture.repository.card(id: original.id)
        #expect(retainedCard == expectedCard)
        #expect(retainedCard.body.utf8.elementsEqual(expectedCard.body.utf8))
        #expect(retainedCard.version == expectedCard.version)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
        if workEnded {
            #expect(try await fixture.repository.drafts().isEmpty)
        } else {
            let retained = try await fixture.repository.draft(id: initial.id)
            #expect(retained.body.utf8.elementsEqual(other.body.utf8))
            #expect(retained.sequence == other.sequence)
        }
    }

    @Test func interruptedPreparationKeepsValuesWithoutPublishingOrChangingTheTemplate() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(title: "連絡", body: "{{宛名}}へ\r\n{{用件}}\0", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let first = UseSessionModel(card: card, draft: draft, storage: fixture.repository)
        first.updateValue("山田さん", for: "宛名")
        first.updateValue("日程を確認します", for: "用件")
        first.updateTitle("山田さんの日程確認")
        #expect(await first.suspend())
        let reopened = try WorkspaceRepository(location: fixture.location)
        let workspace = WorkspaceModel(storage: reopened)
        await workspace.resume(draft)
        guard case .use(let resumed) = workspace.route else {
            Issue.record("Preparation must resume in the confirmation session")
            return
        }
        #expect(resumed.values == ["宛名": "山田さん", "用件": "日程を確認します"])
        #expect(resumed.title == "山田さんの日程確認")
        #expect(resumed.output?.utf8.elementsEqual("山田さんへ\r\n日程を確認します\0".utf8) == true)
        #expect(try await reopened.list(query: WorkspaceQuery()).total == 1)
        #expect(try await reopened.card(id: card.id).body.utf8.elementsEqual(card.body.utf8))
    }

    @Test func preparationCheckpointSuccessIncludesValuesArrivingDuringTheAwait() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let card = try await fixture.create(body: "{{宛名}}へ", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: storage)
        model.updateValue("最初の宛名", for: "宛名")
        let gate = SessionOperationGate()
        await storage.pauseNextCheckpoint(at: gate)
        async let checkpointed = model.checkpoint()
        await gate.waitUntilEntered()
        model.updateValue("訂正した宛名\0", for: "宛名")
        async let overlapping = model.checkpoint()
        await gate.release()
        let mayClose = await checkpointed
        let overlapMayClose = await overlapping
        let retained = try await fixture.repository.draft(id: draft.id)
        #expect(mayClose && overlapMayClose && model.error == nil)
        #expect(retained.values["宛名"]?.utf8.elementsEqual("訂正した宛名\0".utf8) == true)
    }

    @Test func resumedPreparationConflictCopiesNothingAndRescueRetryUsesOneDraft() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "{{宛名}}へ\0", usesVariables: true)
        let initial = try await fixture.repository.preparationDraft(cardID: card.id)
        let first = UseSessionModel(card: card, draft: initial, storage: fixture.repository)
        let storage = SessionStorageProbe(base: fixture.repository)
        let second = UseSessionModel(card: card, draft: initial, storage: storage)
        first.updateValue("別の画面で保持した宛名", for: "宛名")
        #expect(await first.suspend())
        second.updateValue("宛名の変更1", for: "宛名")
        second.updateValue("救出する宛名", for: "宛名")
        let delivery = SessionTextDeliverySpy()
        await second.copy(using: delivery)
        #expect(delivery.bodies.isEmpty && !second.copied && second.error == .staleCheckpoint)
        #expect(second.values["宛名"] == "救出する宛名")
        await storage.failNextPublish(with: .storage(code: 10))
        #expect(!(await second.saveIndependentCompletion()))
        #expect(second.error == .storage(code: 10) && second.hasIndependentRecovery)
        let failedWork = try await fixture.repository.drafts()
        let rescueID = try #require(failedWork.first(where: { $0.id != initial.id })?.id)
        #expect(failedWork.count == 2)
        second.updateValue("訂正した宛名", for: "宛名")
        await storage.failNextPublish(with: .storage(code: 13))
        #expect(!(await second.saveIndependentCompletion()))
        #expect(second.error == .storage(code: 13) && second.hasIndependentRecovery)
        #expect(Set(try await fixture.repository.drafts().map(\.id)) == [initial.id, rescueID])
        #expect(await second.saveIndependentCompletion())
        #expect(second.completionSaved && second.error == nil && !second.hasIndependentRecovery)
        #expect(second.card.body.utf8.elementsEqual("訂正した宛名へ\0".utf8))
        #expect(!(await second.saveIndependentCompletion()))
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 2)
        #expect(try await fixture.repository.drafts().map(\.id) == [initial.id])
        #expect(try await fixture.repository.draft(id: initial.id).values["宛名"] == "別の画面で保持した宛名")
        await second.copy(using: delivery)
        await second.copy(using: delivery)
        #expect(delivery.bodies == ["訂正した宛名へ\0"])
        #expect(try await fixture.repository.card(id: card.id).body == "{{宛名}}へ\0")
    }

    @Test func preparationSuspendBlocksLateValueChanges() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let card = try await fixture.create(body: "{{宛名}}へ", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: storage)
        model.updateValue("確認した宛名", for: "宛名")
        let gate = SessionOperationGate()
        await storage.pauseNextCheckpoint(at: gate)
        async let closed = model.suspend()
        await gate.waitUntilEntered()
        #expect(model.busy)
        model.updateValue("遅れた宛名", for: "宛名")
        #expect(model.values["宛名"] == "確認した宛名")
        await gate.release()
        let didClose = await closed
        #expect(didClose)
        #expect(try await fixture.repository.draft(id: draft.id).values["宛名"] == "確認した宛名")
    }

    @Test(arguments: [false, true])
    func supersededPreparationCanDiscardOnlyItsLocalValuesWithoutCopying(workEnded: Bool) async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let created = try await fixture.create(body: "{{宛名}}へ\0", usesVariables: true)
        let original = try await fixture.repository.card(id: created.id)
        let initial = try await fixture.repository.preparationDraft(cardID: original.id)
        let local = UseSessionModel(card: original, draft: initial, storage: fixture.repository)
        local.updateValue("この画面で破棄する宛名", for: "宛名")
        var other = initial
        try other.update(title: "", body: other.body, values: ["宛名": "別の画面で保持した宛名"])
        _ = try await fixture.repository.checkpoint(other)
        if workEnded {
            try await fixture.repository.discardDraft(id: other.id, expectedSequence: other.sequence)
        }
        #expect(!(await local.suspend()))
        #expect(local.discardsLocalInputOnly)
        #expect(local.error == (workEnded ? .missingDraft : .staleCheckpoint))
        #expect(await local.discard())
        let delivery = SessionTextDeliverySpy()
        await local.copy(using: delivery)
        #expect(delivery.bodies.isEmpty && !local.copied)
        let retainedCard = try await fixture.repository.card(id: original.id)
        #expect(retainedCard == original)
        #expect(retainedCard.body.utf8.elementsEqual(original.body.utf8))
        #expect(retainedCard.version == original.version)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
        if workEnded {
            #expect(try await fixture.repository.drafts().isEmpty)
        } else {
            #expect(try await fixture.repository.draft(id: initial.id).values == other.values)
        }
    }

    @Test func concurrentAndRepeatedCopyCallsDeliverTheConfirmedBytesOnce() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let card = try await fixture.create(body: "{{宛名}}\r\nか\u{3099}\0", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: storage)
        model.updateValue("山田👩🏽‍💻", for: "宛名")
        let delivery = SessionTextDeliverySpy()
        let gate = SessionOperationGate()
        await storage.pauseNextRevalidation(at: gate)
        async let firstCopy: Void = model.copy(using: delivery)
        await gate.waitUntilEntered()
        #expect(model.busy)
        await model.copy(using: delivery)
        await gate.release()
        await firstCopy
        await model.copy(using: delivery)
        #expect(delivery.bodies.count == 1)
        #expect(delivery.bodies.first?.utf8.elementsEqual("山田👩🏽‍💻\r\nか\u{3099}\0".utf8) == true)
        #expect(model.copied && model.error == nil)
        #expect(try await fixture.repository.drafts().isEmpty)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
        #expect(try await fixture.repository.card(id: card.id).body.utf8.elementsEqual(card.body.utf8))
    }

    @Test func cancellationBeforeTheExternalEffectCopiesNothingAndRetainsValues() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let card = try await fixture.create(body: "{{宛名}}へ", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: storage)
        model.updateValue("確認済みの宛名", for: "宛名")
        let delivery = SessionTextDeliverySpy()
        let gate = SessionOperationGate()
        await storage.pauseNextRevalidation(at: gate)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.copy(using: delivery) }
            await gate.waitUntilEntered()
            group.cancelAll()
            await gate.release()
            await group.waitForAll()
        }
        #expect(delivery.bodies.isEmpty && !model.copied && !model.busy)
        #expect(try await fixture.repository.draft(id: draft.id).values["宛名"] == "確認済みの宛名")
        #expect(try await fixture.repository.card(id: card.id).body == "{{宛名}}へ")
    }

    @Test func discardingPreparationCannotPublishOrCopyItsOutput() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let card = try await fixture.create(body: "{{宛名}}へ", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: fixture.repository)
        model.updateValue("利用しない宛名", for: "宛名")
        #expect(await model.discard())
        let delivery = SessionTextDeliverySpy()
        await model.copy(using: delivery)
        #expect(delivery.bodies.isEmpty && !model.copied)
        #expect(try await fixture.repository.drafts().isEmpty)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
    }

    @Test func resumedPreparationKeepsItsOriginalVersionWhenTheSourceChanged() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let original = try await fixture.create(title: "原ひな型", body: "{{宛名}}へ旧内容", usesVariables: true)
        var preparation = try await fixture.repository.preparationDraft(cardID: original.id)
        try preparation.update(title: "相手別の用件", body: preparation.body, values: ["宛名": "山田"])
        _ = try await fixture.repository.checkpoint(preparation)
        var editing = try await fixture.repository.editingDraft(cardID: original.id)
        try editing.update(title: original.title, body: "{{宛名}}へ新内容", values: [:])
        let changed = try await fixture.repository.publish(editing)
        let workspace = WorkspaceModel(storage: fixture.repository)
        await workspace.resume(preparation)
        guard case .use(let resumed) = workspace.route else {
            Issue.record("Preparation must resume without adopting another source revision")
            return
        }
        #expect(resumed.card.version == original.version)
        #expect(resumed.output == "山田へ旧内容")
        let delivery = SessionTextDeliverySpy()
        await resumed.copy(using: delivery)
        #expect(delivery.bodies.isEmpty && !resumed.copied)
        #expect(resumed.error == .conflict)
        #expect(try await fixture.repository.draft(id: preparation.id).baseVersion == original.version)
        #expect(try await fixture.repository.card(id: original.id).version == changed.version)
    }

    @Test func saveFailureKeepsInputDurableAndAnExplicitRetryCanComplete() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let draft = try await fixture.repository.beginDraft(title: "", body: "最初")
        let model = DraftSessionModel(draft: draft, storage: storage)
        let input = "保存障害でも残す\r\nか\u{3099}\0"
        model.update(title: "入力中の名前", body: input)
        await storage.failNextPublish(with: .storage(code: 10))
        #expect(await model.save() == nil)
        #expect(model.error == .storage(code: 10))
        #expect(!model.busy && model.draft.body.utf8.elementsEqual(input.utf8))
        #expect(try await fixture.repository.draft(id: draft.id).body.utf8.elementsEqual(input.utf8))
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 0)
        let saved = try #require(await model.save())
        #expect(try await fixture.repository.card(id: saved.id).body.utf8.elementsEqual(input.utf8))
        #expect(model.error == nil)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 1)
    }

    @Test func checkpointFailureKeepsTheInputAndDoesNotPretendItWasSaved() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let draft = try await fixture.repository.beginDraft(title: "", body: "保持済み")
        let model = DraftSessionModel(draft: draft, storage: storage)
        model.update(body: "保持に失敗した最新入力")
        await storage.failNextCheckpoint(with: .storage(code: 13))
        #expect(!(await model.suspend()))
        #expect(model.error == .storage(code: 13) && !model.hasCheckpoint && !model.busy)
        #expect(model.draft.body == "保持に失敗した最新入力")
        #expect(try await fixture.repository.draft(id: draft.id).body == "保持済み")
        await storage.failNextCheckpoint(with: .storage(code: 13))
        #expect(!(await model.discard()) && !model.discardsLocalInputOnly)
        #expect(try await fixture.repository.draft(id: draft.id).body == "保持済み")
        #expect(await model.suspend())
        #expect(try await fixture.repository.draft(id: draft.id).body == "保持に失敗した最新入力")
    }

    @Test func completedCopyIsNeverRepeatedWhenDraftCleanupFails() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let storage = SessionStorageProbe(base: fixture.repository)
        let card = try await fixture.create(body: "{{宛名}}へ", usesVariables: true)
        let draft = try await fixture.repository.preparationDraft(cardID: card.id)
        let model = UseSessionModel(card: card, draft: draft, storage: storage)
        model.updateValue("山田", for: "宛名")
        await storage.failNextDiscard(with: .storage(code: 10))
        let delivery = SessionTextDeliverySpy()
        await model.copy(using: delivery)
        #expect(model.copied && model.error == .storage(code: 10))
        #expect(delivery.bodies == ["山田へ"])
        #expect(try await fixture.repository.draft(id: draft.id).values["宛名"] == "山田")
        await model.copy(using: delivery)
        #expect(delivery.bodies == ["山田へ"])
        #expect(await storage.discardAttempts == 1)
        #expect(await model.discard())
        await model.copy(using: delivery)
        #expect(delivery.bodies == ["山田へ"])
        #expect(try await fixture.repository.drafts().isEmpty)
    }

    @Test func uncommittedCompositionCannotPublishOrCopy() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let draft = try await fixture.repository.beginDraft(title: "", body: "にほんご")
        let editor = DraftSessionModel(draft: draft, storage: fixture.repository)
        editor.isComposing = true
        #expect(await editor.save() == nil)
        #expect(try await fixture.repository.list(query: WorkspaceQuery()).total == 0)
        editor.isComposing = false
        let saved = try #require(await editor.save())
        let use = UseSessionModel(card: saved, draft: nil, storage: fixture.repository)
        use.isComposing = true
        let delivery = SessionTextDeliverySpy()
        await use.copy(using: delivery)
        #expect(delivery.bodies.isEmpty && !use.copied)
        use.isComposing = false
        await use.copy(using: delivery)
        #expect(delivery.bodies == ["にほんご"])
    }

    @Test func literalCodeOpensWithoutPreparationAndCopiesItsOriginalBytesOnce() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let original = "{{name}}\r\n{{ helper }}\0か\u{3099}👩🏽‍💻"
        let card = try await fixture.create(title: "コード例", body: original)
        let workspace = WorkspaceModel(storage: fixture.repository)
        await workspace.use(card)
        guard case .use(let model) = workspace.route else {
            Issue.record("Literal code must open directly for confirmation")
            return
        }
        #expect(model.draft == nil && model.names.isEmpty)
        #expect(model.output?.utf8.elementsEqual(original.utf8) == true)
        let delivery = SessionTextDeliverySpy()
        await model.copy(using: delivery)
        await model.copy(using: delivery)
        #expect(delivery.bodies.count == 1)
        #expect(delivery.bodies.first?.utf8.elementsEqual(original.utf8) == true)
        #expect(model.copied && model.error == nil)
        #expect(try await fixture.repository.drafts().isEmpty)
        #expect(try await fixture.repository.card(id: card.id).body.utf8.elementsEqual(original.utf8))
    }

    @Test func simultaneousEntryOpeningsCannotReplaceTheReservedOrDisplayedWork() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let saved = try await fixture.create(title: "別の保存文", body: "外から開く別の文章")
        let storage = SessionStorageProbe(base: fixture.repository)
        let workspace = WorkspaceModel(storage: storage)
        let gate = SessionOperationGate()
        await storage.pauseNextBeginDraft(at: gate)
        async let opening: Void = workspace.create(title: "最初の作業", body: "保持する入力")
        await gate.waitUntilEntered()
        let pending = try await fixture.repository.drafts()
        let first = try #require(pending.first)
        #expect(pending.count == 1 && first.title == "最初の作業")
        #expect(workspace.hasOpenWork)
        await workspace.use(cardID: saved.id)
        await workspace.create(title: "競合する作成", body: "表示を置き換えない")
        #expect(workspace.route == nil)
        await gate.release()
        await opening
        guard case .editor(let editor) = workspace.route else {
            Issue.record("The first reserved opening must retain its editing route")
            return
        }
        #expect(editor.id == first.id)
        editor.update(body: "最初の作業で続けた入力\0")
        #expect(await editor.checkpoint())
        await workspace.use(cardID: saved.id)
        guard case .editor(let stillEditing) = workspace.route else {
            Issue.record("A later external entry must not replace displayed editing work")
            return
        }
        #expect(stillEditing === editor)
        let retained = try await fixture.repository.drafts()
        #expect(retained.count == 1 && retained.first?.id == first.id)
        #expect(retained.first?.body.utf8.elementsEqual("最初の作業で続けた入力\0".utf8) == true)
        #expect(try await fixture.repository.card(id: saved.id).body == "外から開く別の文章")
    }

    @Test func changedSearchNeverPresentsPriorResultsDuringWaitingOrFailure() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        let first = try await fixture.create(title: "田中", body: "旧条件の文章")
        let second = try await fixture.create(title: "山田", body: "次の文章")
        let storage = SessionStorageProbe(base: fixture.repository)
        let model = WorkspaceModel(storage: storage)
        await model.refresh(search: "田中")
        #expect(model.cards.map(\.id) == [first.id])
        let gate = SessionOperationGate()
        await storage.pauseNextList(at: gate)
        await storage.failNextList(with: .unavailable)
        async let refreshed: Void = model.refresh(search: "山田")
        await gate.waitUntilEntered()
        #expect(model.loading && model.cards.isEmpty && model.total == 0 && !model.hasMore)
        await gate.release()
        await refreshed
        #expect(model.error == .unavailable && model.cards.isEmpty && !model.loading)
        await model.refresh(search: "山田")
        #expect(model.error == nil && model.cards.map(\.id) == [second.id])
        let sameQuery = SessionOperationGate()
        await storage.pauseNextList(at: sameQuery)
        async let reloaded: Void = model.refresh(search: "山田")
        await sameQuery.waitUntilEntered()
        #expect(model.cards.map(\.id) == [second.id])
        await sameQuery.release()
        await reloaded
    }

    @Test func cancelledRefreshDoesNotLeaveLoadingStuck() async throws {
        let fixture = try SessionWorkspaceFixture()
        defer { fixture.removeFiles() }
        _ = try await fixture.create(body: "保存済み")
        let storage = SessionStorageProbe(base: fixture.repository)
        let model = WorkspaceModel(storage: storage)
        let gate = SessionOperationGate()
        await storage.pauseNextList(at: gate)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.refresh() }
            await gate.waitUntilEntered()
            group.cancelAll()
            await gate.release()
            await group.waitForAll()
        }
        #expect(!model.loading)
        await model.refresh()
        #expect(!model.loading && model.total == 1 && model.error == nil)
    }
}

extension UIIntegrationTests {
    @Suite("Home entry remains available during refresh", .serialized)
    @MainActor
    struct WorkspaceHomeActionTests {
        @Test func creatingFromTheMountedToolbarDoesNotWaitForAnActivationRefresh() async throws {
            let fixture = try SessionWorkspaceFixture()
            defer { fixture.removeFiles() }
            let created = try await fixture.create(body: "既存の原文\r\nか\u{3099}👩🏽‍💻")
            let original = try await fixture.repository.card(id: created.id)
            let storage = SessionStorageProbe(base: fixture.repository)
            let model = WorkspaceModel(storage: storage)
            let host = try ViewTestHost()
            defer { host.close() }
            let view = WorkspaceHomeView(model: model, storage: storage, delivery: SessionTextDeliverySpy())
            host.show(AnyView(view), phase: .inactive)
            try await host.wait {
                model.total == 1 && !model.loading && mountedHomeCreateAction(in: host.window) != nil
            }

            let refresh = SessionOperationGate()
            await storage.pauseNextList(at: refresh)
            do {
                host.show(AnyView(view), phase: .active)
                let deadline = ContinuousClock.now + .seconds(3)
                while !(await refresh.isEntered), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                try #require(await refresh.isEntered, "The mounted active transition must begin a refresh")
                try #require(model.loading && model.route == nil)
                try #require(mountedHomeCreateAction(in: host.window)).activate()
                let presentationDeadline = ContinuousClock.now + .seconds(3)
                while !mountedHomeEditorIsVisible(in: host.window), ContinuousClock.now < presentationDeadline {
                    host.controller.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(10))
                }
                let openedDuringRefresh = mountedHomeEditorIsVisible(in: host.window)
                await refresh.release()
                try await host.wait { !model.loading }
                if !openedDuringRefresh {
                    // Prove this same public UIKit action reaches the product once
                    // the read finishes, rather than blaming an undispatchable tap.
                    try #require(mountedHomeCreateAction(in: host.window)).activate()
                    try await host.wait { mountedHomeEditorIsVisible(in: host.window) }
                }
                guard case .editor(let editor) = model.route else {
                    Issue.record("The toolbar action must present the new editing session")
                    return
                }
                let work = try await fixture.repository.drafts()
                #expect(work.count == 1 && work.first?.id == editor.id)
                #expect(work.first?.body.isEmpty == true)
                #expect(try await fixture.repository.card(id: original.id) == original)
                #expect(openedDuringRefresh, "A background activation read must not silently discard the user's create action")
            } catch {
                await refresh.release()
                throw error
            }
        }
    }
}

@MainActor
private enum MountedHomeCreateAction {
    case control(UIControl, UIControl.Event)
    case barItem(UIBarButtonItem, Selector)

    func activate() throws {
        switch self {
        case .control(let control, let event):
            try #require(control.isEnabled && control.window != nil)
            control.sendActions(for: event)
        case .barItem(let item, let action):
            try #require(item.isEnabled)
            try #require(UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil))
        }
    }
}

@MainActor
private func mountedHomeCreateAction(in view: UIView) -> MountedHomeCreateAction? {
    if view.accessibilityIdentifier == "workspace.create" {
        var candidate: UIView? = view
        while let current = candidate {
            if let control = current as? UIControl {
                if control.allControlEvents.contains(.primaryActionTriggered) { return .control(control, .primaryActionTriggered) }
                if control.allControlEvents.contains(.touchUpInside) { return .control(control, .touchUpInside) }
            }
            candidate = current.superview
        }
    }
    if let bar = view as? UINavigationBar,
       let item = bar.topItem?.rightBarButtonItems?.first(where: { $0.accessibilityIdentifier == "workspace.create" }),
       let action = item.action {
        return .barItem(item, action)
    }
    return view.subviews.lazy.compactMap { mountedHomeCreateAction(in: $0) }.first
}

@MainActor
private func mountedHomeEditorIsVisible(in view: UIView) -> Bool {
    if view.accessibilityIdentifier == "workspace.editor.body", view is UITextView, view.window != nil { return true }
    return view.subviews.contains { mountedHomeEditorIsVisible(in: $0) }
}

@MainActor
private final class SessionTextDeliverySpy: TextDelivery {
    private(set) var bodies: [String] = []
    func copy(_ body: String) { bodies.append(body) }
}

private actor SessionOperationGate {
    private var entered = false
    var isEntered: Bool { entered }
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var released = false
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

private actor SessionStorageProbe: WorkspaceStorage {
    private let base: WorkspaceRepository
    private var checkpointFailure: WorkspaceError?
    private var publishFailure: WorkspaceError?
    private var discardFailure: WorkspaceError?
    private var checkpointGate: SessionOperationGate?
    private var revalidationGate: SessionOperationGate?
    private var listGate: SessionOperationGate?
    private var listFailure: WorkspaceError?
    private var beginDraftGate: SessionOperationGate?
    private(set) var discardAttempts = 0

    init(base: WorkspaceRepository) { self.base = base }

    func failNextCheckpoint(with error: WorkspaceError) { checkpointFailure = error }
    func failNextPublish(with error: WorkspaceError) { publishFailure = error }
    func failNextDiscard(with error: WorkspaceError) { discardFailure = error }
    func pauseNextCheckpoint(at gate: SessionOperationGate) { checkpointGate = gate }
    func pauseNextRevalidation(at gate: SessionOperationGate) { revalidationGate = gate }
    func pauseNextList(at gate: SessionOperationGate) { listGate = gate }
    func failNextList(with error: WorkspaceError) { listFailure = error }
    func pauseNextBeginDraft(at gate: SessionOperationGate) { beginDraftGate = gate }

    func list(query: WorkspaceQuery) async throws -> WorkspacePage {
        if let gate = listGate {
            listGate = nil
            await gate.pause()
        }
        if let failure = listFailure {
            listFailure = nil
            throw failure
        }
        return try await base.list(query: query)
    }

    func card(id: UUID) async throws -> TextCard { try await base.card(id: id) }
    func drafts() async throws -> [WorkDraft] { try await base.drafts() }
    func draft(id: UUID) async throws -> WorkDraft { try await base.draft(id: id) }
    func beginDraft(title: String, body: String) async throws -> WorkDraft {
        let draft = try await base.beginDraft(title: title, body: body)
        if let gate = beginDraftGate {
            beginDraftGate = nil
            await gate.pause()
        }
        return draft
    }
    func editingDraft(cardID: UUID) async throws -> WorkDraft { try await base.editingDraft(cardID: cardID) }
    func preparationDraft(cardID: UUID) async throws -> WorkDraft { try await base.preparationDraft(cardID: cardID) }

    func checkpoint(_ draft: WorkDraft) async throws -> WorkDraft {
        if let gate = checkpointGate {
            checkpointGate = nil
            await gate.pause()
        }
        if let failure = checkpointFailure {
            checkpointFailure = nil
            throw failure
        }
        return try await base.checkpoint(draft)
    }

    func publish(_ draft: WorkDraft) async throws -> TextCard {
        if let failure = publishFailure {
            publishFailure = nil
            _ = try await base.checkpoint(draft)
            throw failure
        }
        return try await base.publish(draft)
    }

    func discardDraft(id: UUID, expectedSequence: Int) async throws {
        discardAttempts += 1
        if let failure = discardFailure {
            discardFailure = nil
            throw failure
        }
        try await base.discardDraft(id: id, expectedSequence: expectedSequence)
    }

    func setPinned(_ pinned: Bool, cardID: UUID, expectedVersion: Int) async throws -> TextCard {
        try await base.setPinned(pinned, cardID: cardID, expectedVersion: expectedVersion)
    }

    func trash(cardID: UUID, expectedVersion: Int) async throws -> TextCard {
        try await base.trash(cardID: cardID, expectedVersion: expectedVersion)
    }

    func restore(cardID: UUID, expectedVersion: Int) async throws -> TextCard {
        try await base.restore(cardID: cardID, expectedVersion: expectedVersion)
    }

    func keyboardSummaries(limit: Int) async throws -> [PreparedCardSummary] { try await base.keyboardSummaries(limit: limit) }

    func revalidate(cardID: UUID, expectedVersion: Int) async throws -> TextCard {
        if let gate = revalidationGate {
            revalidationGate = nil
            await gate.pause()
        }
        return try await base.revalidate(cardID: cardID, expectedVersion: expectedVersion)
    }
}

private struct SessionWorkspaceFixture: Sendable {
    let directory: URL
    let location: URL
    let repository: WorkspaceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("session-tests-\(UUID().uuidString)", isDirectory: true)
        location = directory.appendingPathComponent("workspace.sqlite")
        repository = try WorkspaceRepository(location: location)
    }

    func create(title: String = "", body: String, usesVariables: Bool = false) async throws -> TextCard {
        var draft = try await repository.beginDraft(title: title, body: body)
        try draft.update(title: title, body: body, values: [:], usesVariables: usesVariables)
        return try await repository.publish(draft)
    }

    func removeFiles() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove session fixture: \(error)") }
    }
}
