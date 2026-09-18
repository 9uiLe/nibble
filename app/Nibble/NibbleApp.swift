import AppMacros
import SwiftUI
import UIKit

@main
struct NibbleApp: App {
    private let store = SnippetStorage.sharedContainer()

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store, effects: SystemLibraryEffects())
                .modifier(NibbleInterface())
                .background(SceneInterfaceDefaults())
        }
    }
}

/// Apply native control traits at the app scene, including system presentations.
@Equatable(.mainActor)
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
