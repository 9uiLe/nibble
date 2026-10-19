import SwiftUI

@main
struct NibbleApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceEntryView()
                .background(MainScenePrivacyShield())
        }
    }
}
