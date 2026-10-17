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
            Button { perform(.edit) } label: {
                HStack(spacing: 6) {
                    SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, unusedSince: unusedSince)
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                        .foregroundStyle(Color.nibbleSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snippet.\(item.id)")
                .accessibilityLabel(item.pinned ? "ピン留め、\(item.displayTitle)" : item.displayTitle)
                .accessibilityValue(unusedSince.map {
                    SnippetUsagePresentation.inactiveMessage + "、最後にコピーした日 " + $0.formatted(date: .numeric, time: .omitted)
                } ?? "")
                .accessibilityHint("編集します")
        }
    }
}
