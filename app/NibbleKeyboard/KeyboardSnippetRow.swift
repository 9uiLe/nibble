import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardSnippetRow: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @Binding var detailOrigin: UUID?
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    var body: some View {
        HStack(spacing: 0) {
            Button { taskOwner.startTask(item, as: .insert, on: model) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    SnippetHeading(title: item.displayTitle, pinned: item.pinned, style: .keyboard)
                    Text(verbatim: item.preview).font(.nibbleBody).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(.leading, 12).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("\(item.displayTitle)を入力")
                .accessibilityIdentifier("keyboard.insert.\(item.id)")
            Button {
                detailOrigin = item.id
                model.openDetail(item)
            } label: {
                Label("全文を見る", systemImage: "ellipsis.circle")
                    .labelStyle(.titleAndIcon).font(.nibbleBody).fixedSize()
                    .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 60).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("\(item.displayTitle)の全文を見る")
                .accessibilityFocused(focus, equals: "more.\(item.id)").accessibilityIdentifier("keyboard.more.\(item.id)")
        }
        .background(model.notice?.insertedID == item.id ? Color.nibbleKeyboardHighlight : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.nibbleSeparator).frame(height: 0.5).padding(.horizontal, 12) }
    }
}
