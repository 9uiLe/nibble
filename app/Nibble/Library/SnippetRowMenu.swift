import AppMacros
import SwiftUI

@Equatable
struct SnippetRowMenu: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let isTrash: Bool
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        if isTrash {
            Button("復元", systemImage: "arrow.uturn.backward") { perform(.restore) }
            Button("完全に削除", systemImage: "trash", role: .destructive) { perform(.permanentlyDelete) }
                .accessibilityIdentifier("permanentlyDelete.\(item.id)")
        } else {
            Button("編集", systemImage: "square.and.pencil") { perform(.edit) }
            Button(item.pinned ? "ピン留めを解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { perform(.pin) }
            Button("削除", systemImage: "trash", role: .destructive) { perform(.delete) }
                .accessibilityIdentifier("delete.\(item.id)")
        }
    }
}
