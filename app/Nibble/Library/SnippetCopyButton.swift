import AppMacros
import SwiftUI

@Equatable
struct SnippetCopyButton: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        Button { perform(.copy) } label: {
            Image(systemName: "doc.on.doc")
                .font(.callout)
                .frame(width: 36, height: 36)
                .background(Color.nibbleSoft, in: .rect(cornerRadius: 10))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(item.displayTitle)をコピー")
        .accessibilityIdentifier("copy.\(item.id)")
    }
}
