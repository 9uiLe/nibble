import AppMacros
import SwiftUI

@Equatable
struct RootScreenHeading: View {
    private let inputRevision = UUID()
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ScreenHeading(title: "nibble")
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("設定")
            .accessibilityIdentifier("navigation.settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
