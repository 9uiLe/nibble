import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct FloatingTabBar: View {
    private let inputRevision = UUID()
    static let reservedHeight: CGFloat = 76
    @Binding var selection: AppTab
    @Environment(\.tabBarScrollState) private var tabScroll
    private var isCompact: Bool { tabScroll?.isCompact == true }

    var body: some View {
        AnimationScope(.smooth(duration: 0.28), value: isCompact, name: "Navigation.TabBar") {
            HStack(spacing: 0) {
                TabNavigationButton(tab: .library, title: "一覧", symbol: selection == .library ? "house.fill" : "house", selection: $selection, isCompact: isCompact)
                TabNavigationButton(tab: .search, title: "検索", symbol: "magnifyingglass", selection: $selection, isCompact: isCompact)
                TabNavigationButton(tab: .settings, title: "設定", symbol: "gearshape", selection: $selection, isCompact: isCompact)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            // One transform keeps the material, selection and hit regions together.
            // 52 * 0.85 = 44.2pt, preserving the minimum compact hit height.
            .scaleEffect(isCompact ? 0.85 : 1, anchor: .bottom)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .frame(height: Self.reservedHeight - 8, alignment: .bottom)
        .padding(.bottom, 8)
    }
}
