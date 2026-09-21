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
        if let failure = model.failure {
            ScrollView {
                Text(failure)
                    .font(.nibbleBody)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let page = model.page, !page.items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(page.items) { item in
                        VStack(spacing: 0) {
                            KeyboardSnippetRow(item: item, model: model, taskOwner: taskOwner, focus: focus, detailOrigin: $detailOrigin)
                            if item.id != page.items.last?.id { Divider().padding(.horizontal, 12) }
                        }
                    }
                }
            }
            .id(model.request)
            .disabled(!model.isCurrent || model.isUsing)
            .overlay { if model.loading { ProgressView().accessibilityLabel("読み込み中") } }
        } else if model.loading {
            ProgressView().accessibilityLabel("読み込み中")
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    Text(model.request.filter == .pinned ? "ピン留めした項目はありません" : "保存した項目はありません")
                        .font(.subheadline.weight(.semibold))
                    Text(model.request.filter == .pinned
                        ? "「すべて」で項目の「…」を開くと、ピン留めできます。"
                        : "nibbleで文章やURLを保存すると、ここから入力できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity)
            }
        }
    }
}
