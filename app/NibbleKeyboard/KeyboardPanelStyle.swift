import SwiftUI

struct KeyboardPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 8))
            .clipShape(.rect(cornerRadius: 8))
            .padding(.horizontal, 8)
    }
}
