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
    // Keep the last card laid out while fading out; expiry must not tear down its host.
    @State private var lastNotice: LibraryModel.Notice?

    var body: some View {
        AnimationScope(.smooth(duration: 0.3), value: model.notice != nil, name: "Library.Notice") {
            // Animate a persistent container, including the first card's insertion.
            ZStack {
                if let notice = model.notice ?? lastNotice {
                    LibraryNoticeContent(notice: notice,
                                         isRestoring: notice.undoID.map { model.restoringIDs.contains($0) } ?? false,
                                         restore: restore)
                }
            }
            .opacity(model.notice == nil ? 0 : 1)
            .offset(y: model.notice == nil ? 8 : 0)
            .allowsHitTesting(model.notice != nil)
            .accessibilityHidden(model.notice == nil)
        }
        .onChange(of: model.notice, initial: true) {
            if let notice = model.notice { lastNotice = notice }
        }
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
    }
}
