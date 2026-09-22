import AppMacros
import SwiftUI

@Equatable
struct PinButton: View {
    enum Style { case labeled, icon }
    private let inputRevision = UUID()
    let pinned: Bool
    var style: Style = .labeled
    let action: () -> Void

    private var title: String { pinned ? "ピン留めを解除" : "ピン留め" }

    var body: some View {
        Button(action: action) {
            if style == .icon {
                Image(systemName: pinned ? "pin.fill" : "pin")
            } else {
                Label(title, systemImage: pinned ? "pin.slash" : "pin")
            }
        }
        .accessibilityLabel(title)
    }
}
