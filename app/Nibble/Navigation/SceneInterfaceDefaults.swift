import AppMacros
import SwiftUI
import UIKit

@Equatable(.mainActor)
struct SceneInterfaceDefaults: UIViewRepresentable {
    func makeUIView(context: Context) -> TraitView { TraitView() }
    func updateUIView(_ uiView: TraitView, context: Context) { uiView.applyDefaults() }
    final class TraitView: UIView {
        func applyDefaults() {
            guard let scene = window?.windowScene else { return }
            NibbleInterface.apply(to: &scene.traitOverrides)
        }
        override func didMoveToWindow() { super.didMoveToWindow(); applyDefaults() }
    }
}
