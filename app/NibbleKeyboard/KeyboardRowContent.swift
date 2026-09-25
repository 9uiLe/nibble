import AppMacros
import SwiftUI

@Equatable
struct KeyboardRowContent: @MainActor EquatableBodyView {
    let item: SnippetSummary
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SnippetHeading(title: item.displayTitle, pinned: item.pinned, style: .keyboard)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("入力").font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }
            Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
