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

    var body: some View {
        AnimationScope(.easeOut(duration: 0.16), value: model.notice != nil, name: "Library.Notice") {
            if let notice = model.notice {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(notice.message, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                        if let subject = notice.subject {
                            Text(subject).font(.subheadline).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice.announcement)
                    .accessibilityIdentifier("library.notice")
                    if let id = notice.undoID {
                        Button { restore(id) } label: {
                            Text("元に戻す")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                            .accessibilityIdentifier("library.undo")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.success, trigger: model.feedback)
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
    }
}
