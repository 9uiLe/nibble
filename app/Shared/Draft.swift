import Foundation

/// An immutable identity and base revision with monotonically ordered input snapshots.
struct Draft: Identifiable, Equatable, Sendable {
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

    var isDisposable: Bool {
        (title.isEmpty && body.isEmpty) || (snippetID != nil && sequence == 0)
    }

    /// Swift String equality folds canonically equivalent Unicode; persistence must retain bytes.
    func canReplace(_ stored: Draft) -> Bool {
        guard id == stored.id, snippetID == stored.snippetID, baseRevision == stored.baseRevision else { return false }
        return sequence > stored.sequence || (sequence == stored.sequence
            && SnippetText.hasSameBytes(title, stored.title)
            && SnippetText.hasSameBytes(body, stored.body))
    }
}

/// Library rows never retain draft bodies. Opening a row reads the current draft by ID.
struct DraftSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
}
