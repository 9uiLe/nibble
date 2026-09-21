import AppMacros
import SwiftUI

@Equatable
struct SnippetRowMainContent: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let isTrash: Bool
    let unusedSince: Date?
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        if isTrash {
            SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, unusedSince: unusedSince)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .accessibilityIdentifier("snippet.\(item.id)")
        } else {
            Button { perform(.edit) } label: { SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, unusedSince: unusedSince) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snippet.\(item.id)")
                .accessibilityLabel(item.pinned ? "ピン留め、\(item.displayTitle)" : item.displayTitle)
                .accessibilityValue(unusedSince.map {
                    "30日以上コピーしていません、最後にコピーした日 " + $0.formatted(date: .numeric, time: .omitted)
                } ?? "")
                .accessibilityHint("編集します")
        }
    }
}
