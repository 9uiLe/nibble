import AppMacros
import SwiftUI

@Equatable
struct KeyboardListContent: View {
    private enum Content {
        case failure(String)
        case items([SnippetSummary])
        case loading
        case empty(KeyboardFilter)
    }

    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    @Binding var detailOrigin: UUID?
    @Binding var listPosition: UUID?

    private var content: Content {
        if let failure = model.failure { return .failure(failure) }
        if let page = model.page, !page.items.isEmpty { return .items(page.items) }
        if model.loading { return .loading }
        return .empty(model.request.filter)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let notice = model.notice, !notice.expires {
                    KeyboardStatusMessage(notice: notice)
                        .font(.nibbleBody)
                        .padding(16)
                    Divider().padding(.horizontal, 12)
                }
                switch content {
                case .failure(let failure):
                    Text(failure)
                        .font(.nibbleBody)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                case .items(let items):
                    ForEach(items) { item in
                        VStack(spacing: 0) {
                            KeyboardSnippetRow(item: item, model: model, taskOwner: taskOwner, focus: focus, detailOrigin: $detailOrigin)
                            if item.id != items.last?.id { Divider().padding(.horizontal, 12) }
                        }
                        .id(item.id)
                    }
                    .disabled(!model.isCurrent || model.isUsing)
                case .loading:
                    ProgressView().accessibilityLabel("読み込み中")
                case .empty(let filter):
                    VStack(spacing: 6) {
                        Text(filter == .pinned ? "ピン留めした項目はありません" : "保存した項目はありません")
                            .font(.subheadline.weight(.semibold))
                        Text(filter == .pinned
                            ? "「すべて」で項目の「全文を見る」を押すと、ピン留めできます。"
                            : "nibbleで文章やURLを保存すると、ここから入力できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity)
                }
            }
            .scrollTargetLayout()
        }
        .id(model.request)
        .scrollPosition(id: $listPosition)
        .onChange(of: model.request) { listPosition = nil }
        .overlay {
            if model.loading, model.page?.items.isEmpty == false {
                ProgressView().accessibilityLabel("読み込み中")
            }
        }
    }
}
