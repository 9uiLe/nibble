import Foundation

/// An editor can persist its draft and finish it, but cannot browse or delete saved items.
protocol DraftEditing: Sendable {
    func updateDraft(_ draft: Draft) async throws
    func keepDraft(_ draft: Draft) async throws
    func discardDraft(_ draft: Draft) async throws
    @discardableResult func save(_ draft: Draft, asNew: Bool) async throws -> UUID
}

/// Opening and resuming are separate from the lifetime of the presented editor.
protocol LibraryOpening: Sendable {
    func beginDraft(snippetID: UUID?, body: String) async throws -> Draft
    func editingDraft(for id: UUID) async throws -> Draft
    func draft(_ id: UUID) async throws -> Draft
}

enum SnippetMutation: Sendable {
    case delete, restore, permanentlyDelete
}

/// A mutation's subject is read in the transaction that commits the change.
struct SnippetMutationResult: Sendable {
    let subject: String
}

protocol SnippetUsageRecording: Sendable {
    func recordUse(_ use: SnippetUse) async throws
}

protocol LibraryStorage: LibraryReading, LibraryOpening, SnippetUsageRecording {
    func savedBody(_ id: UUID) async throws -> String
    func setPinned(_ pinned: Bool, id: UUID) async throws
    func mutate(_ mutation: SnippetMutation, id: UUID) async throws -> SnippetMutationResult
    func keepDraft(_ draft: Draft) async throws
}
