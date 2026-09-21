import SwiftUI

@main
struct NibbleApp: App {
    private let store = SnippetStore(location: SnippetLocation.database)

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store, effects: SystemLibraryEffects())
                .modifier(NibbleInterface())
                .background(SceneInterfaceDefaults())
        }
    }
}
