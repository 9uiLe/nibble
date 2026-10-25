import AppMacros
import SwiftUI
import UIKit

@MainActor
@Equatable(.mainActor)
struct PreparedKeyboardInputModeButton: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let button: UIButton

    func makeUIView(context: Context) -> UIButton { button }
    func updateUIView(_ uiView: UIButton, context: Context) {}
}
