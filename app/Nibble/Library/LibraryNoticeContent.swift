import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryNoticeContent: View {
    private let inputRevision = UUID()
    let notice: LibraryModel.Notice
    let isRestoring: Bool
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.message).font(.subheadline.weight(.semibold))
                if let subject = notice.subject { Text(verbatim: subject).font(.footnote).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(notice.announcement)
            .accessibilityIdentifier("library.notice")
            if notice.undoID != nil {
                Button { taskOwner.startTask(.undoNotice(notice.id), on: model) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .modifier(IconControlStyle(foreground: .nibbleSelection, background: .nibbleOnSelection))
                }.buttonStyle(.plain).disabled(isRestoring)
                    .accessibilityLabel("元に戻す").accessibilityHint(notice.subject ?? "")
                    .accessibilityIdentifier("library.undo")
            }
        }
        .foregroundStyle(Color.nibbleOnSelection).padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color.nibbleSelection, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}
