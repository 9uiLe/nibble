import AppMacros
import SwiftUI

@Equatable
struct SettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()
    let showTrash: () -> Void

    var body: some View {
        SettingsList(version: .current, showTrash: showTrash)
        .background(Color.nibbleCanvas)
        .navigationTitle("設定")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
