import AppMacros
import SwiftUI

@Equatable(.mainActor)
struct KeyboardInputModeButton: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let button: UIButton
    func makeUIView(context: Context) -> UIButton { button }
    func updateUIView(_ uiView: UIButton, context: Context) { }
}
