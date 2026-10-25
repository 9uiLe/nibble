import AppMacros
import SwiftUI

@Equatable
struct PreparedKeyboardRow: @MainActor EquatableBodyView {
    let summary: PreparedCardSummary

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: WorkspacePresentation.title(summary.title, body: summary.preview))
                .font(.body.weight(.semibold)).lineLimit(2)
            Text(verbatim: summary.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}
