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
}

/// Library rows retain only a bounded preview of each draft. Opening a row reads the current draft by ID.
struct DraftSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let updatedAt: Date

    var displayTitle: String {
        let value = Snippet.displayTitle(title: title, body: preview)
        return value.isEmpty ? "新しい下書き" : value
    }
}
