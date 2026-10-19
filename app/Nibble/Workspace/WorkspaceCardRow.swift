import AppMacros
import SwiftUI

@Equatable
struct WorkspaceCardRow: @MainActor EquatableBodyView {
    let card: TextCard
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: WorkspacePresentation.title(card)).font(.headline).lineLimit(2)
                if card.pinned { Image(systemName: "pin.fill").accessibilityLabel("ピン留め") }
            }
            Text(verbatim: String(card.body.prefix(180)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let origin = card.originTitle {
                Text("「\(origin)」から作った固定文")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if card.usesVariables && !TextTemplate(card.body).names.isEmpty {
                Label("差し替えて使う", systemImage: "text.badge.plus")
                    .font(.caption).foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
