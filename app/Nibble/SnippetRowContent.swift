import AppMacros
import SwiftUI

/// Only displayed values cross this gate. Actions and observable state belong to LibraryView.
@Equatable
struct SnippetRowContent: EquatableBodyView {
    let title: String
    let preview: String
    let pinned: Bool

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.nibbleAccent) }
                Text(Snippet.displayTitle(title: title, body: preview)).font(.headline).foregroundStyle(.primary).lineLimit(2)
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(.rect)
    }
}
