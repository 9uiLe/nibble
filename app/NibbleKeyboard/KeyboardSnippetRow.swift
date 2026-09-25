import AppMacros
import SwiftUI

@Equatable
struct KeyboardSnippetRow: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    @Binding var detailOrigin: UUID?

    var body: some View {
        HStack(spacing: 8) {
            Button { taskOwner.startTask(item, as: .insert, on: model) } label: {
                KeyboardRowContent(item: item)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)を入力")
            .accessibilityValue(item.pinned ? "ピン留め済み" : "")
            .accessibilityHint("保存した本文を入力中のアプリに挿入します")
            .accessibilityIdentifier("keyboard.insert.\(item.id)")

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 1)

            Button {
                detailOrigin = item.id
                model.openDetail(item)
            } label: {
                HStack(spacing: 3) {
                    Text("全文を見る")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)の全文を見る")
            .accessibilityIdentifier("keyboard.more.\(item.id)")
            .accessibilityFocused(focus, equals: "more.\(item.id)")
        }
        .buttonStyle(KeyboardRowStyle())
        .background(model.notice?.insertedID == item.id ? Color(uiColor: .systemBlue).opacity(0.14) : .clear)
    }
}
