import AppMacros
import SwiftUI

@MainActor @Equatable
struct RootScreenHeading: View {
    private let inputRevision = UUID()
    @SkipEquatable let openSettings: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            ScreenHeading(title: "nibble")
            Button(action: openSettings) {
                Label("設定", systemImage: "gearshape")
                    .labelStyle(.iconOnly).font(.system(size: 19))
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
                .buttonStyle(.plain).accessibilityIdentifier("navigation.settings")
        }.padding(.horizontal, 20).padding(.top, 4)
    }
}
