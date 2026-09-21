import AppMacros
import SwiftUI
import UIKit

/// Apply native control traits at the app scene, including system presentations.
@Equatable(.mainActor)
struct SceneInterfaceDefaults: UIViewRepresentable {
    func makeUIView(context: Context) -> TraitView { TraitView() }
    func updateUIView(_ view: TraitView, context: Context) {}

    final class TraitView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { NibbleInterface.apply(to: &scene.traitOverrides) }
        }
    }
}
