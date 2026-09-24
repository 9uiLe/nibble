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
        HStack(spacing: 0) {
            Button { taskOwner.startTask(item, as: .insert, on: model) } label: {
                KeyboardRowContent(item: item)
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)を入力")
            .accessibilityValue(item.pinned ? "ピン留め済み" : "")
            .accessibilityHint("保存した本文を入力中のアプリに挿入します")
            .accessibilityIdentifier("keyboard.insert.\(item.id)")
            Button {
                detailOrigin = item.id
                model.openDetail(item)
            } label: {
                Text("全文").font(.caption.weight(.medium))
                    .frame(width: 50, height: 58).contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)の全文と操作")
            .accessibilityIdentifier("keyboard.more.\(item.id)")
            .accessibilityFocused(focus, equals: "more.\(item.id)")
        }
        .buttonStyle(KeyboardRowStyle())
        .background(model.notice?.insertedID == item.id ? Color(uiColor: .systemBlue).opacity(0.14) : .clear)
    }
}
