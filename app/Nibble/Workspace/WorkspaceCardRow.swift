import AppMacros
import SwiftUI

@Equatable
struct WorkspaceCardRow: @MainActor EquatableBodyView {
    let card: TextCard
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: WorkspacePresentation.title(card))
                .font(.system(.body, weight: .semibold))
                .lineLimit(2)
                .frame(minHeight: 24, alignment: .topLeading)
            Text(verbatim: String(card.body.prefix(180)))
                .font(.subheadline)
                .foregroundStyle(WorkspaceStyle.secondary)
                .lineLimit(1)
                .frame(minHeight: 22, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
