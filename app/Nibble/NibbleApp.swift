import SwiftUI

@main
struct NibbleApp: App {
    private let library = SnippetStore(location: SnippetLocation.database)
    var body: some Scene {
        WindowGroup {
            AppRootView(store: library, effects: SystemLibraryEffects())
                .modifier(NibbleInterface())
                .environment(\.iosDesignTokens, .nibble)
                .background(SceneInterfaceDefaults())
        }
    }
}
