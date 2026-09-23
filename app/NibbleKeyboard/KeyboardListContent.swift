import AppMacros
import SwiftUI

@Equatable
struct KeyboardListContent: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    @Binding var detailOrigin: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let notice = model.notice, !notice.expires {
                    KeyboardStatusMessage(notice: notice)
                        .font(.nibbleBody)
                        .padding(16)
                    Divider().padding(.horizontal, 12)
                }
                if let failure = model.failure {
                    Text(failure)
                        .font(.nibbleBody)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                } else if let page = model.page, !page.items.isEmpty {
                    ForEach(page.items) { item in
                        VStack(spacing: 0) {
                            KeyboardSnippetRow(item: item, model: model, taskOwner: taskOwner, focus: focus, detailOrigin: $detailOrigin)
                            if item.id != page.items.last?.id { Divider().padding(.horizontal, 12) }
                        }
                    }
                    .disabled(!model.isCurrent || model.isUsing)
                } else if model.loading {
                    ProgressView().accessibilityLabel("読み込み中")
                } else {
                    VStack(spacing: 6) {
                        Text(model.request.filter == .pinned ? "ピン留めした項目はありません" : "保存した項目はありません")
                            .font(.subheadline.weight(.semibold))
                        Text(model.request.filter == .pinned
                            ? "「すべて」で項目の「全文」を開くと、ピン留めできます。"
                            : "nibbleで文章やURLを保存すると、ここから入力できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity)
                }
            }
        }
        .id(model.request)
        .overlay {
            if model.loading, model.page?.items.isEmpty == false {
                ProgressView().accessibilityLabel("読み込み中")
            }
        }
    }
}
