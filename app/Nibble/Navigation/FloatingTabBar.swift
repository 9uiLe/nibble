import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct FloatingTabBar: View {
    private let inputRevision = UUID()
    @Binding var selection: AppTab
    @Environment(\.tabBarScrollState) private var tabScroll
    private var isCompact: Bool { tabScroll?.isCompact == true }

    var body: some View {
        AnimationScope(.smooth(duration: 0.28), value: isCompact, name: "Navigation.TabBar") {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabNavigationButton(tab: tab, selection: $selection, isCompact: isCompact)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            // One transform keeps the material, selection and hit regions together.
            // buttonHeight * compactScale = 44.2pt, preserving the minimum compact hit height.
            .scaleEffect(isCompact ? TabBarMetrics.compactScale : 1, anchor: .bottom)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .frame(height: TabBarMetrics.reservedHeight - TabBarMetrics.bottomSpacing, alignment: .bottom)
        .padding(.bottom, TabBarMetrics.bottomSpacing)
    }
}
