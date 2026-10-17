import AppMacros
import SwiftUI

@Equatable
struct SnippetCopyButton: View {
    private let inputRevision = UUID()
    let item: SnippetSummary
    let perform: (SnippetRow.Action) -> Void

    var body: some View {
        Button { perform(.copy) } label: {
            VStack(spacing: 2) {
                Image(systemName: "doc.on.doc")
                    .font(.callout.weight(.medium))
                Text("コピー")
                    .font(.caption2.weight(.semibold))
            }
                .foregroundStyle(Color.nibblePrimary)
                .frame(width: 56, height: 56)
                .background(Color.nibbleSoft, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(item.displayTitle)をコピー")
        .accessibilityIdentifier("copy.\(item.id)")
    }
}
