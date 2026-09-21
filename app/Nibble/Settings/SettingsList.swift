import AppMacros
import SwiftUI

@Equatable
struct SettingsList: View {
    private let inputRevision = UUID()
    let version: AppVersion
    let showTrash: () -> Void

    var body: some View {
        List {
            Group {
                Section {
                    Button(action: showTrash) {
                        SettingsDisclosureLabel(title: "削除した項目", systemImage: "trash")
                    }
                    .accessibilityIdentifier("library.trash")
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
                } footer: {
                    Text("バージョン \(version.display)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                        .accessibilityIdentifier("settings.version")
                }
                .listSectionSeparator(.hidden, edges: .bottom)
            }
            .font(.nibbleTitle)
            .listRowBackground(Color.clear)
        }
        .modifier(LibraryListStyle())
    }
}
