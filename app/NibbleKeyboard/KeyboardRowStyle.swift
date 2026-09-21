import SwiftUI

struct KeyboardRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.10) : .clear)
            .opacity(isEnabled ? 1 : 0.45)
    }
}
