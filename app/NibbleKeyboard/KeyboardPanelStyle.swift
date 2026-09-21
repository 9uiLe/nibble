import SwiftUI

struct KeyboardPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 13))
            .clipShape(.rect(cornerRadius: 13))
            .padding(.horizontal, 10)
    }
}
