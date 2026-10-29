import Foundation
import Observation

@MainActor @Observable
final class PromptSessionModel: Identifiable {
    let id: UUID
    private let storage: any WorkspaceStorage
    private(set) var card: TextCard
    private(set) var editor: DraftSessionModel?
    private(set) var error: WorkspaceError?
    private(set) var busy = false
    private(set) var copied = false
    var renameTitle: String

    init(card: TextCard, storage: any WorkspaceStorage) {
        id = card.id
        self.card = card
        self.storage = storage
        renameTitle = card.title
    }

    func beginEditing() async {
        guard !busy, editor == nil else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await storage.revalidate(cardID: card.id, expectedVersion: card.version)
            let draft = try await storage.editingDraft(cardID: card.id)
            guard draft.baseVersion == card.version else {
                try await storage.discardDraft(id: draft.id, expectedSequence: draft.sequence)
                throw WorkspaceError.conflict
            }
            editor = DraftSessionModel(draft: draft, storage: storage, contentKind: .prompt)
            error = nil
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func finishedEditing(saved: Bool) async {
        defer { editor = nil }
        guard saved else { return }
        do {
            card = try await storage.card(id: card.id)
            renameTitle = card.title
            copied = false
            error = nil
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func rename() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            card = try await storage.rename(cardID: card.id, expectedVersion: card.version, title: renameTitle)
            copied = false
            error = nil
            return true
        } catch {
            self.error = WorkspaceError.normalize(error)
            return false
        }
    }

    func copy(using delivery: any TextDelivery) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let current = try await storage.revalidate(cardID: card.id, expectedVersion: card.version)
            try Task.checkCancellation()
            delivery.copy(current.body)
            copied = true
            error = nil
        } catch { self.error = WorkspaceError.normalize(error) }
    }

    func trash() async -> TextCard? {
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            let deleted = try await storage.trash(cardID: card.id, expectedVersion: card.version)
            error = nil
            return deleted
        } catch {
            self.error = WorkspaceError.normalize(error)
            return nil
        }
    }
}
