import AppMacros
import SwiftUI

@Equatable
struct SnippetRowContent: @MainActor EquatableBodyView {
    let title: String
    let preview: String
    let pinned: Bool
    let unusedSince: Date?
    init(title: String, preview: String, pinned: Bool, unusedSince: Date? = nil) {
        self.title = title; self.preview = preview; self.pinned = pinned; self.unusedSince = unusedSince
    }
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            SnippetHeading(title: SnippetTextPresentation(title: title, body: preview).title, pinned: pinned, style: .library)
            Text(verbatim: preview.replacingOccurrences(of: "\n", with: " "))
                .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary).lineLimit(2)
            if let unusedSince {
                Text("\(SnippetUsagePresentation.inactiveMessage)・\(unusedSince.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(Color.nibbleSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
