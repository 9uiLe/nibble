import AppMacros
import SwiftUI

@Equatable
struct LibrarySettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    let showTrash: () -> Void

    var body: some View {
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
        .modifier(LibraryNavigationTitle(title: "設定"))
    }
}
