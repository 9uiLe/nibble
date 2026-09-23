import AppMacros
import SwiftUI

/// Only displayed values cross this gate. Actions and observable state belong to AppRootView.
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

    private var text: SnippetTextPresentation { SnippetTextPresentation(title: title, body: preview) }

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            SnippetHeading(title: text.title, pinned: pinned, style: .library)
            if text.hasExplicitTitle {
                Text(preview.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                    .font(.nibbleBody).foregroundStyle(.secondary).lineLimit(2)
            }
            if let unusedSince {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SnippetUsagePresentation.inactiveMessage)
                    Text("最後のコピー \(unusedSince, format: .dateTime.year().month().day())")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("snippet.unused")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(.rect)
    }
}
