import AppMacros
import SwiftUI

@Equatable
struct SettingsList: View {
    private let inputRevision = UUID()
    let version: AppVersion
    let showTrash: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink {
                    KeyboardGuideView()
                } label: {
                    SettingsDisclosureLabel(title: "nibbleキーボード", detail: "追加・使い方・フルアクセス",
                                            systemImage: "keyboard", showsChevron: false)
                }
                .accessibilityIdentifier("settings.keyboard")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .listRowSeparator(.hidden, edges: .top)
                Button(action: showTrash) {
                    SettingsDisclosureLabel(title: "削除した項目", detail: "復元・完全削除",
                                            systemImage: "trash", showsChevron: true)
                }
                .accessibilityIdentifier("library.trash")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsDisclosureLabel(title: "nibbleについて", detail: "操作とデータについて",
                                            systemImage: "info.circle", showsChevron: false)
                }
                .accessibilityIdentifier("settings.about")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .listRowSeparator(.hidden, edges: .bottom)
            } footer: {
                Text("バージョン \(version.display)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                    .accessibilityIdentifier("settings.version")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)
        }
        .modifier(LibraryListStyle())
    }
}
