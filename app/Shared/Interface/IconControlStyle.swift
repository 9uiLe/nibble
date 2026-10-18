import SwiftUI

struct IconControlStyle: ViewModifier {
    var foreground: Color = .primary
    var background: Color = .nibbleSoft
    func body(content: Content) -> some View {
        content.labelStyle(.iconOnly).font(.system(size: 18, weight: .medium))
            .foregroundStyle(foreground).frame(width: 36, height: 36)
            .background(background, in: .circle)
            .frame(width: 44, height: 44).contentShape(.rect)
    }
}
