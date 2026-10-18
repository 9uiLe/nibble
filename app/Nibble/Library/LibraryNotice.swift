import AppMacros
import ScopedAnimation
import SwiftUI

@MainActor @Equatable
struct LibraryNotice: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    @State private var displayed: LibraryModel.Notice?
    var body: some View {
        AnimationScope(.smooth(duration: 0.3), value: model.notice?.id, name: "Library.Notice") {
            Group {
                if let notice = model.notice ?? displayed {
                    LibraryNoticeContent(notice: notice, isRestoring: notice.undoID.map { model.restoringIDs.contains($0) } ?? false, model: model, taskOwner: taskOwner)
                }
            }
            .opacity(model.notice == nil ? 0 : 1)
            .offset(y: model.notice == nil ? 8 : 0)
            .allowsHitTesting(model.notice != nil).accessibilityHidden(model.notice == nil)
        }
        .onChange(of: model.notice, initial: true) { if let notice = model.notice { displayed = notice } }
        .task(id: model.notice?.id) { if let notice = model.notice { await model.expireNotice(id: notice.id) } }
    }
}
