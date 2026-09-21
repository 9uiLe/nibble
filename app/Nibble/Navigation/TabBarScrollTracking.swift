import SwiftUI

extension EnvironmentValues {
    @Entry var tabBarScrollState: TabBarScrollState?
}

struct TabBarScrollTracking: ViewModifier {
    var enabled = true
    @Environment(\.tabBarScrollState) private var tabScroll
    @State private var phase = ScrollPhase.idle

    func body(content: Content) -> some View {
        content
            // TabView hosts do not pass the root's custom bar inset into every scroll view.
            // Keep the final row/paragraph reachable above the bar at either size.
            .contentMargins(.bottom, enabled ? TabBarMetrics.reservedHeight : 0, for: .scrollContent)
            .onScrollPhaseChange { _, next in
                phase = next
                if next == .interacting { tabScroll?.beginGesture() }
            }
            .onScrollGeometryChange(for: Int.self) { geometry in
                let maximum = max(0, geometry.contentSize.height + geometry.contentInsets.top
                                  + geometry.contentInsets.bottom - geometry.containerSize.height)
                return Int(max(0, min(maximum, geometry.contentOffset.y + geometry.contentInsets.top)))
            } action: { old, new in
                if enabled {
                    tabScroll?.observe(from: old, to: new, phase: phase)
                }
            }
            .onAppear { if enabled { tabScroll?.expand() } }
    }
}
