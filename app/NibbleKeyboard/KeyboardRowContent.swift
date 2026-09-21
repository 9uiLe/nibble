import AppMacros
import SwiftUI

@Equatable
struct KeyboardRowContent: @MainActor EquatableBodyView {
    let item: SnippetSummary
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(item.displayTitle).font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
