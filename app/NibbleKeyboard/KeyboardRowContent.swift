import AppMacros
import SwiftUI

@Equatable
struct KeyboardRowContent: @MainActor EquatableBodyView {
    let item: SnippetSummary
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            SnippetHeading(title: item.displayTitle, pinned: item.pinned, style: .keyboard)
                .lineLimit(1)
            Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
