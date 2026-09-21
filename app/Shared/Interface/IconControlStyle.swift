import SwiftUI

/// Compact appearance with a separate, forgiving touch target.
struct IconControlStyle: ViewModifier {
    var foreground: Color = .primary
    var background: Color = .nibbleSoft

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.system(size: InterfaceMetrics.controlSymbolSize, weight: .medium))
            .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
            .foregroundStyle(foreground)
            .background(background, in: .circle)
            .frame(width: InterfaceMetrics.touchSize, height: InterfaceMetrics.touchSize)
            .contentShape(.rect)
    }
}
