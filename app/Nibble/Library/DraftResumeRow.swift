import AppMacros
import SwiftUI

@Equatable
struct DraftResumeRow: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let draft: DraftSummary

    var body: some View {
        IOSCard {
            HStack(spacing: 8) {
                Button { taskOwner.startTask(.open(.draft(draft.id)), on: model) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        IOSBadge("下書き", symbol: "square.and.pencil")
                        HStack(spacing: 8) {
                            Text(draft.displayTitle).font(.nibbleTitle).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("再開").font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下書きを再開、\(draft.displayTitle)")
                .accessibilityIdentifier("draft.\(draft.id)")
                if model.page.hasMoreDrafts {
                    Button { model.filter = .drafts } label: {
                        Text("ほか\(model.page.counts.drafts - 1)件")
                            .font(.caption2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下書きをすべて見る、\(model.page.counts.drafts)件")
                    .accessibilityIdentifier("library.allDrafts")
                }
            }
        }
    }
}
