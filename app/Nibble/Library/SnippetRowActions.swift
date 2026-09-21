import AppMacros
import SwiftUI

@Equatable
struct SnippetRowActions: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let isTrash: Bool
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isTrash {
                Button { perform(.restore) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.body)
                        .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(item.displayTitle)を復元")
                    .accessibilityIdentifier("restore.\(item.id)")
            } else { SnippetCopyButton(item: item, perform: perform) }
            Menu { SnippetRowMenu(item: item, isTrash: isTrash, perform: perform) } label: {
                Image(systemName: "ellipsis").font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(item.displayTitle)のその他の操作")
            .accessibilityIdentifier("more.\(item.id)")
        }
    }
}
