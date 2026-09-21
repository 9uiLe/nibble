import AppMacros
import SwiftUI

@Equatable
struct SettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()
    @SkipEquatable let library: LibraryModel

    let showTrash: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RootScreenHeading(title: "設定", model: library)
            SettingsList(version: .current, showTrash: showTrash)
        }
        .background(Color.nibbleCanvas)
        .navigationTitle("設定")
        .toolbar(.hidden, for: .navigationBar)
    }
}
