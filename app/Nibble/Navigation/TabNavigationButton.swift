import AppMacros
import SwiftUI

@Equatable
struct TabNavigationButton: View {
    private let inputRevision = UUID()
    let tab: AppTab
    @Binding var selection: AppTab
    let isCompact: Bool
    @Environment(\.tabBarScrollState) private var tabScroll

    var body: some View {
        Button {
            selection = tab
            tabScroll?.expand()
        } label: {
            TabIcon(symbol: tab.symbol(isSelected: selection == tab), size: TabBarMetrics.iconSize)
                // Compensate for the outer transform to preserve the specified compact icon size.
                .scaleEffect(isCompact ? TabBarMetrics.compactIconScale : 1)
                .frame(maxWidth: .infinity)
                .frame(height: TabBarMetrics.buttonHeight)
                .background(selection == tab ? Color.primary.opacity(0.09) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .accessibilityLabel(tab.title)
        .accessibilityValue(selection == tab ? "選択中" : "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("navigation.tab.\(tab.rawValue)")
    }
}
