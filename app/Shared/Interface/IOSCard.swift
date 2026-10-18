import AppMacros
import SwiftUI

@MainActor @Equatable
struct IOSCard<Content: View>: View {
    private let inputRevision = UUID()
    @SkipEquatable private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.nibbleSurface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.nibbleBorder, lineWidth: 1) }
    }
}
