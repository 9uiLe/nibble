import AppMacros
import SwiftUI

/// Only displayed values cross this gate. Actions and observable state belong to LibraryView.
@Equatable
struct SnippetRowContent: @MainActor EquatableBodyView {
    let title: String
    let preview: String
    let pinned: Bool
    let expanded: Bool

    init(title: String, preview: String, pinned: Bool, expanded: Bool = false) {
        self.title = title
        self.preview = preview
        self.pinned = pinned
        self.expanded = expanded
    }

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.nibbleAccent) }
                Text(Snippet.displayTitle(title: title, body: preview)).font(.headline).foregroundStyle(.primary).lineLimit(expanded ? nil : 2)
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(.rect)
    }
}
