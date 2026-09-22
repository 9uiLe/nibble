import AppMacros
import SwiftUI

@Equatable
struct DraftResumeRow: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let draft: DraftSummary

    var body: some View {
        HStack(spacing: 4) {
            Button { taskOwner.startTask(.open(.draft(draft.id)), on: model) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("下書きを再開").font(.footnote.weight(.medium))
                        Text(draft.displayTitle).font(.caption2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !model.page.hasMoreDrafts {
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
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
        .foregroundStyle(Color.nibbleAccent)
        .padding(.horizontal, 12)
        .background(Color.nibbleSoft, in: .rect(cornerRadius: 12))
    }
}
