import Foundation

/// An immutable identity and base revision with monotonically ordered input snapshots.
struct Draft: Identifiable, Equatable, Sendable {
    enum Replacement { case newer, identical, rejected }
    /// Persistent identity and input ordering, without allocating the stored body.
    struct Checkpoint: Equatable, Sendable {
        let id: UUID
        let snippetID: UUID?
        let baseRevision: Int
        let sequence: Int

        func belongsToSameSession(as other: Self) -> Bool {
            id == other.id && snippetID == other.snippetID && baseRevision == other.baseRevision
        }
    }

    let id: UUID
    let snippetID: UUID?
    let baseRevision: Int
    var title: String {
        didSet { if !SnippetText.hasSameBytes(oldValue, title) { sequence += 1 } }
    }
    var body: String {
        didSet { if !SnippetText.hasSameBytes(oldValue, body) { sequence += 1 } }
    }
    private(set) var sequence: Int = 0

    var checkpoint: Checkpoint {
        Checkpoint(id: id, snippetID: snippetID, baseRevision: baseRevision, sequence: sequence)
    }

    func canAutosave(over stored: Checkpoint) -> Bool {
        checkpoint.belongsToSameSession(as: stored) && sequence > stored.sequence
    }

    func replacement(of stored: Checkpoint, title: String, body: String) -> Replacement {
        if canAutosave(over: stored) { return .newer }
        return checkpoint == stored && SnippetText.hasSameBytes(self.title, title)
            && SnippetText.hasSameBytes(self.body, body) ? .identical : .rejected
    }

    var isDisposable: Bool {
        (title.isEmpty && body.isEmpty) || (snippetID != nil && sequence == 0)
    }
}

/// Library rows retain only a bounded preview of each draft. Opening a row reads the current draft by ID.
struct DraftSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let updatedAt: Date
}
