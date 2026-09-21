import AppMacros
import SwiftUI

@Equatable
struct SettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    let showTrash: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(title: "設定")
            settingsList
        }
        .background(Color.nibbleCanvas)
        .navigationTitle("設定")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var settingsList: some View {
        List {
            Group {
                Section {
                    Button("削除した項目", systemImage: "trash", action: showTrash)
                        .accessibilityIdentifier("library.trash")
                } header: {
                    Text("保存した項目")
                        .font(.footnote.weight(.semibold))
                }
                Section {
                    NavigationLink {
                        KeyboardGuideView()
                    } label: {
                        Label("nibbleキーボード", systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("settings.keyboard")
                }
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("nibbleについて", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settings.about")
                }
            }
            .font(.nibbleTitle)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.nibbleCanvas)
    }
}
