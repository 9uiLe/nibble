import SwiftUI
import UIKit

@main
struct NibbleApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .modifier(NibbleInterface())
                .background(SceneInterfaceDefaults())
        }
    }
}

/// Apply native control traits at the app scene, including system presentations.
private struct SceneInterfaceDefaults: UIViewRepresentable {
    func makeUIView(context: Context) -> TraitView { TraitView() }
    func updateUIView(_ view: TraitView, context: Context) {}

    final class TraitView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { NibbleInterface.apply(to: &scene.traitOverrides) }
        }
    }
}
