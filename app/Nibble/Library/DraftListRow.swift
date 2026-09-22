import AppMacros
import SwiftUI

@Equatable
struct DraftListRow: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let draft: DraftSummary

    var body: some View {
        Button { taskOwner.startTask(.open(.draft(draft.id)), on: model) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.body).foregroundStyle(Color.nibbleAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.nibbleSoft, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    SnippetHeading(title: draft.displayTitle, pinned: false, style: .library)
                    if draft.textPresentation.hasExplicitTitle {
                        Text(draft.preview).font(.nibbleBody).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(minHeight: 36)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("下書き、\(draft.displayTitle)")
        .accessibilityValue(!draft.textPresentation.hasExplicitTitle
            ? Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
            : Text("\(draft.preview)、\(draft.updatedAt, format: .dateTime.month().day().hour().minute())"))
        .accessibilityHint("編集を再開します")
        .accessibilityIdentifier("draft.\(draft.id)")
    }
}
