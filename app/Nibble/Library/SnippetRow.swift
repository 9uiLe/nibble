import AppMacros
import SwiftUI

/// Value-driven row; the screen decides how and when to execute each intent.
@Equatable
struct SnippetRow: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    enum Action { case edit, copy, pin, delete, restore, permanentlyDelete }
    let item: SnippetSummary
    let isTrash: Bool
    var unusedSince: Date?
    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 4) {
            SnippetRowMainContent(item: item, isTrash: isTrash, unusedSince: unusedSince, perform: perform)
            SnippetRowActions(item: item, isTrash: isTrash, perform: perform)
        }
        .padding(.vertical, 14)
        .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .contextMenu { SnippetRowMenu(item: item, isTrash: isTrash, perform: perform) }
        .swipeActions(edge: .trailing, allowsFullSwipe: !isTrash) {
            if isTrash {
                Button("完全に削除", role: .destructive) { perform(.permanentlyDelete) }
            } else {
                Button("削除", systemImage: "trash", role: .destructive) { perform(.delete) }
                    .accessibilityIdentifier("swipe.delete.\(item.id)")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isTrash {
                Button(item.pinned ? "ピン留めを解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") {
                    perform(.pin)
                }
                .tint(.nibbleAccent)
                .accessibilityIdentifier("swipe.pin.\(item.id)")
            }
        }
    }
}
