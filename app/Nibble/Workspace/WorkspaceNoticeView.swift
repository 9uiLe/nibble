import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceNoticeView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: WorkspaceModel
    @SkipEquatable let notice: WorkspaceModel.Notice
    @State private var tasks = ViewTaskStore()

    var body: some View {
        HStack(spacing: 12) {
            switch notice {
            case .saved: Text("文章を保存しました").accessibilityIdentifier("workspace.notice.text")
            case .restored: Text("文章をごみ箱から戻しました").accessibilityIdentifier("workspace.notice.text")
            case .pinned(let pinned): Text(pinned ? "ピン留めしました" : "ピン留めを外しました").accessibilityIdentifier("workspace.notice.text")
            case .trashed(let card):
                Text("「\(WorkspacePresentation.title(card))」をごみ箱へ移しました")
                    .accessibilityIdentifier("workspace.notice.text")
                Button("元に戻す") { startTask(card) }
                    .accessibilityIdentifier("workspace.undo")
            }
            Spacer(minLength: 0)
            Button("通知を閉じる", systemImage: "xmark") { model.notice = nil }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .background(.regularMaterial)
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask(_ card: TextCard) {
        tasks.start(id: "workspace.undo", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.restore(card)
        }
    }
}
