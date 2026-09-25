import AppMacros
import SwiftUI

@Equatable
struct SnippetRowMenu: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        Button("編集", systemImage: "square.and.pencil") { perform(.edit) }
        PinButton(pinned: item.pinned, action: { perform(.pin) })
        Button("削除", systemImage: "trash", role: .destructive) { perform(.delete) }
            .accessibilityIdentifier("delete.\(item.id)")
    }
}
