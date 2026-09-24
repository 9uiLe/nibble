import SwiftUI

@main
struct NibbleApp: App {
    private let store = SnippetStore(location: SnippetLocation.database)
    private let advertising: any AdvertisingContent = UnconfiguredAdvertising()

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store, effects: SystemLibraryEffects(), advertising: advertising)
                .modifier(NibbleInterface())
                .background(SceneInterfaceDefaults())
        }
    }
}
