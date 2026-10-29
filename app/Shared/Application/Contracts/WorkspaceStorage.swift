import Foundation

protocol WorkspaceStorage: Sendable {
    func list(query: WorkspaceQuery) async throws -> WorkspacePage
    func card(id: UUID) async throws -> TextCard
    func drafts() async throws -> [WorkDraft]
    func draft(id: UUID) async throws -> WorkDraft
    func beginDraft(title: String, body: String) async throws -> WorkDraft
    func editingDraft(cardID: UUID) async throws -> WorkDraft
    func preparationDraft(cardID: UUID) async throws -> WorkDraft
    func checkpoint(_ draft: WorkDraft) async throws -> WorkDraft
    func publish(_ draft: WorkDraft) async throws -> TextCard
    func discardDraft(id: UUID, expectedSequence: Int) async throws
    func setPinned(_ pinned: Bool, cardID: UUID, expectedVersion: Int) async throws -> TextCard
    func trash(cardID: UUID, expectedVersion: Int) async throws -> TextCard
    func rename(cardID: UUID, expectedVersion: Int, title: String) async throws -> TextCard
    func restore(cardID: UUID, expectedVersion: Int) async throws -> TextCard
    func keyboardSummaries(limit: Int) async throws -> [PreparedCardSummary]
    func revalidate(cardID: UUID, expectedVersion: Int) async throws -> TextCard
}
