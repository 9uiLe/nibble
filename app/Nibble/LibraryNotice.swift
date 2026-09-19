import AppMacros
import SwiftUI
import ScopedAnimation

/// Observes transient feedback separately from the list's persisted content.
@Equatable
struct LibraryNotice: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @SkipEquatable let model: LibraryModel
    let restore: (UUID) -> Void
    var inAccessory = false

    var body: some View {
        Group {
            if inAccessory {
                noticeContent
            } else {
                AnimationScope(.easeOut(duration: 0.16), value: model.notice != nil, name: "Library.Notice") {
                    noticeContent
                }
            }
        }
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
    }

    @ViewBuilder private var noticeContent: some View {
        if let notice = model.notice {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(notice.message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subject = notice.subject {
                        Text(subject).font(inAccessory ? .caption : .subheadline)
                            .lineLimit(inAccessory ? 1 : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.announcement)
                .accessibilityIdentifier("library.notice")
                if let id = notice.undoID {
                    Button { restore(notice.id) } label: {
                        Text("元に戻す")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44).contentShape(.rect)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.borderless)
                        .disabled(model.restoringIDs.contains(id))
                        .accessibilityHint("\(notice.subject ?? "スニペット")を復元します")
                        .accessibilityIdentifier("library.undo")
                }
            }
            .padding(.horizontal, inAccessory ? 16 : 20)
            .padding(.vertical, inAccessory ? 0 : 8)
            .background {
                if !inAccessory { RoundedRectangle(cornerRadius: 20).fill(.regularMaterial) }
            }
            .transition(inAccessory ? .identity : .opacity)
        }
    }
}
