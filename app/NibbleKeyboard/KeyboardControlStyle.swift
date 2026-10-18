import SwiftUI

struct KeyboardControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).contentShape(.rect)
            .foregroundStyle(.primary).opacity(configuration.isPressed ? 0.55 : 1)
    }
}
