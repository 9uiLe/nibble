import AppMacros
import SwiftUI

/// Only displayed values cross this gate. Actions and observable state belong to LibraryView.
@Equatable
struct SnippetRowContent: @MainActor EquatableBodyView {
    let title: String
    let preview: String
    let pinned: Bool
    let unusedSince: Date?

    init(title: String, preview: String, pinned: Bool, unusedSince: Date? = nil) {
        self.title = title
        self.preview = preview
        self.pinned = pinned
        self.unusedSince = unusedSince
    }

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.nibbleAccent) }
                Text(Snippet.displayTitle(title: title, body: preview))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            }
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(preview.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            if let unusedSince {
                VStack(alignment: .leading, spacing: 2) {
                    Text("30日以上コピーしていません")
                    Text("最後のコピー \(unusedSince, format: .dateTime.year().month().day())")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("snippet.unused")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(.rect)
    }
}
