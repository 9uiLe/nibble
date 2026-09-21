import AppMacros
import SwiftUI

@Equatable
struct AboutSection<Content: View>: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    let title: LocalizedStringKey
    @SkipEquatable @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.nibbleTitle)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
