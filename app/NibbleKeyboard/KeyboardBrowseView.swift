import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardBrowseView: View {
    private enum Content { case loading, empty, rows([SnippetSummary]) }
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @Binding var listPosition: UUID?
    @Binding var detailOrigin: UUID?
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    private var content: Content {
        if let rows = model.page?.items, !rows.isEmpty { return .rows(rows) }
        return model.loading ? .loading : .empty
    }
    var body: some View {
        VStack(spacing: 0) {
            KeyboardFilterBar(model: model, focus: focus)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let failure = model.failure { Text(failure).font(.nibbleBody).padding(12) }
                    if let notice = model.notice, !notice.expires { KeyboardStatusMessage(notice: notice).padding(12) }
                    switch content {
                    case .loading: ProgressView("読み込み中").padding()
                    case .empty:
                        VStack(spacing: 8) {
                            Text(model.request.filter == .pinned ? "ピン留めした項目はありません" : "保存した項目はありません").font(.nibbleTitle)
                            Text(model.request.filter == .pinned ? "「すべて」から全文を開くとピン留めできます。" : "nibbleで文章やURLを保存してください。").font(.nibbleBody)
                        }.padding(16)
                    case .rows(let rows):
                        ForEach(rows) { row in
                            KeyboardSnippetRow(item: row, model: model, taskOwner: taskOwner, detailOrigin: $detailOrigin, focus: focus)
                                .id(row.id)
                        }.disabled(!model.isCurrent || model.isUsing)
                    }
                }.scrollTargetLayout()
            }
            .scrollPosition(id: $listPosition).id(model.request)
            .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
