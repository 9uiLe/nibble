import Foundation

enum DraftSaveMode: Sendable {
    case save
    case saveAsNew
}

protocol DraftEditing: Sendable {
    @discardableResult
    func save(_ draft: Draft, mode: DraftSaveMode) async throws -> UUID
    func updateDraft(_ draft: Draft) async throws
    func discardDraft(_ draft: Draft) async throws
    func keepDraft(_ draft: Draft) async throws
}

protocol LibraryOpening: Sendable {
    func draft(_ id: UUID) async throws -> Draft
    func editingDraft(for id: UUID) async throws -> Draft
    func beginDraft(target: DraftTarget, body: String) async throws -> Draft
}

enum SnippetMutation: Sendable {
    case delete
    case restore
    case permanentlyDelete
}

protocol SnippetUsageRecording: Sendable {
    func recordUse(_ use: SnippetUse) async throws
}

protocol LibraryStorage: LibraryReading, LibraryOpening, SnippetUsageRecording {
    func mutate(_ mutation: SnippetMutation, id: UUID) async throws -> SnippetSummary
    func setPinned(_ pinned: Bool, id: UUID) async throws
    func savedBody(_ id: UUID) async throws -> String
    func keepDraft(_ draft: Draft) async throws
}
