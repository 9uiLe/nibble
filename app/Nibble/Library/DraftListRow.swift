import AppMacros
import SwiftUI

@MainActor @Equatable
struct DraftListRow: View {
    private let inputRevision = UUID()
    let draft: DraftSummary
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    var body: some View {
        Button { taskOwner.startTask(.open(.draft(draft.id)), on: model) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: draft.displayTitle).font(.nibbleTitle)
                    Text(verbatim: draft.preview).font(.nibbleBody).lineLimit(2).foregroundStyle(Color.nibbleSecondary)
                    Text(draft.updatedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(Color.nibbleSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel("下書きを再開、\(draft.displayTitle)").accessibilityIdentifier("draft.\(draft.id)")
    }
}
