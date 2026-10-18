import AppMacros
import SwiftUI

@MainActor @Equatable
struct DraftResumeRow: View {
    private let inputRevision = UUID()
    let draft: DraftSummary
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    var body: some View {
        Button { taskOwner.startTask(.open(.draft(draft.id)), on: model) } label: {
            IOSCard {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        IOSBadge("下書き")
                        Text(verbatim: draft.displayTitle).font(.nibbleTitle).lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Label("再開", systemImage: "chevron.right").font(.nibbleTitle)
                }
            }
        }.buttonStyle(.plain).accessibilityLabel("下書きを再開、\(draft.displayTitle)").accessibilityIdentifier("draft.\(draft.id)")
    }
}
