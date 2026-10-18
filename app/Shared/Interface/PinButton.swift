import AppMacros
import SwiftUI

@MainActor @Equatable
struct PinButton: View {
    enum Style { case labeled, icon }
    private let inputRevision = UUID()
    let pinned: Bool
    var style: Style = .labeled
    @SkipEquatable let action: () -> Void
    var body: some View {
        Button(action: action) {
            switch style {
            case .icon:
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .frame(width: 44, height: 44).contentShape(.rect)
            case .labeled: Label(pinned ? "ピン留めを解除" : "ピン留め", systemImage: pinned ? "pin.slash" : "pin")
            }
        }
        .accessibilityLabel(pinned ? "ピン留めを解除" : "ピン留め")
    }
}
