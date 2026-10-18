import AppMacros
import SwiftUI

@MainActor @Equatable
struct AboutSection<Content: View>: View {
    private let inputRevision = UUID()
    let title: String
    @SkipEquatable let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.nibbleTitle).accessibilityAddTraits(.isHeader)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
