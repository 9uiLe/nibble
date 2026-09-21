import SwiftUI

struct LibraryListStyle: ViewModifier {
    var tracksTabBar = true

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.nibbleCanvas)
            .modifier(TabBarScrollTracking(enabled: tracksTabBar))
    }
}
