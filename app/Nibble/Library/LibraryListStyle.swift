import SwiftUI

struct LibraryListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .foregroundStyle(Color.nibblePrimary)
            .listRowSeparatorTint(Color.nibbleSeparator)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.nibbleCanvas)
    }
}
