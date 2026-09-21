import AppMacros
import SwiftUI

@Equatable
struct TabNavigationButton: View {
    private let inputRevision = UUID()
    let tab: AppTab
    let title: String
    let symbol: String
    @Binding var selection: AppTab
    let isCompact: Bool
    @Environment(\.tabBarScrollState) private var tabScroll

    var body: some View {
        Button {
            selection = tab
            tabScroll?.expand()
        } label: {
            TabIcon(symbol: symbol, size: 24)
                // The outer 0.85 transform and this transform produce exactly 16pt.
                .scaleEffect(isCompact ? 16 / (24 * 0.85) : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(selection == tab ? Color.primary.opacity(0.09) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection == tab ? "選択中" : "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("navigation.tab.\(tab)")
    }
}
