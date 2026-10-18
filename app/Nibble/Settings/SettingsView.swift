import AppMacros
import SwiftUI

@MainActor @Equatable
struct SettingsView: View {
    private let inputRevision = UUID()
    @SkipEquatable let subscription: ProSubscription
    @SkipEquatable let store: any LibraryStorage & DraftEditing
    @SkipEquatable let effects: any LibraryEffects
    @SkipEquatable let onTrashReturn: () -> Void
    var body: some View {
        SettingsList(version: .current, subscription: subscription, store: store, effects: effects, onTrashReturn: onTrashReturn)
            .navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.visible, for: .navigationBar)
    }
}
