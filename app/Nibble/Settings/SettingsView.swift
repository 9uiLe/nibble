import AppMacros
import SwiftUI

@Equatable
struct SettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()
    @SkipEquatable let subscription: ProSubscription
    @SkipEquatable let store: any LibraryStorage & DraftEditing
    @SkipEquatable let effects: any LibraryEffects
    let onTrashReturn: () -> Void

    var body: some View {
        SettingsList(version: .current, subscription: subscription, store: store,
                     effects: effects, onTrashReturn: onTrashReturn)
        .background(Color.nibbleCanvas)
        .navigationTitle("設定")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
