import AppMacros
import SwiftUI

@Equatable
struct LibraryNoticeContent: View {
    private let inputRevision = UUID()
    let notice: LibraryModel.Notice
    let isRestoring: Bool
    let restore: (UUID) -> Void
    let inWindow: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(notice.message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subject = notice.subject {
                    Text(subject).font(.footnote)
                        .foregroundStyle(Color.nibbleOnSelection.opacity(0.85))
                        .lineLimit(inWindow ? 1 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notice.announcement)
            .accessibilityIdentifier("library.notice")
            if notice.undoID != nil {
                Button { restore(notice.id) } label: {
                    Label("元に戻す", systemImage: "arrow.uturn.backward")
                        .modifier(IconControlStyle(foreground: .nibbleSelection, background: .nibbleOnSelection))
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
                .opacity(isRestoring ? 0.6 : 1)
                .accessibilityHint("\(notice.subject ?? "項目")を復元します")
                .accessibilityIdentifier("library.undo")
            }
        }
        .padding(.horizontal, inWindow ? 16 : 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(Color.nibbleOnSelection)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Color.nibbleSelection)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        }
    }
}
