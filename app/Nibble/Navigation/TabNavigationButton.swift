import AppMacros
import SwiftUI

@Equatable
struct TabNavigationButton: View {
    private let inputRevision = UUID()
    let tab: AppTab
    @Binding var selection: AppTab
    let isCompact: Bool
    @Environment(\.tabBarScrollState) private var tabScroll
    private var iconSize: CGFloat { isCompact ? TabBarMetrics.compactIconSize : TabBarMetrics.iconSize }

    var body: some View {
        Button {
            selection = tab
            tabScroll?.expand()
        } label: {
            TabIcon(symbol: tab.symbol(isSelected: selection == tab), size: TabBarMetrics.iconSize)
                .scaleEffect(isCompact ? TabBarMetrics.compactIconScale : 1)
                .frame(width: iconSize, height: iconSize)
                .padding(.horizontal, TabBarMetrics.iconHorizontalPadding)
                .frame(height: isCompact ? TabBarMetrics.compactButtonHeight : TabBarMetrics.buttonHeight)
                .background(selection == tab ? Color.primary.opacity(0.09) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .accessibilityLabel(tab.title)
        .accessibilityValue(selection == tab ? "選択中" : "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("navigation.tab.\(tab.rawValue)")
    }
}
