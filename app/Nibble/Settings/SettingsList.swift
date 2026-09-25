import AppMacros
import SwiftUI

@Equatable
struct SettingsList: View {
    private let inputRevision = UUID()
    let version: AppVersion
    @SkipEquatable let subscription: ProSubscription
    @SkipEquatable let store: any LibraryStorage & DraftEditing
    @SkipEquatable let effects: any LibraryEffects
    let onTrashReturn: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProView(subscription: subscription)
                } label: {
                    SettingsDisclosureLabel(title: "nibble Pro", detail: !subscription.checked ? "登録状態を確認中" : subscription.isActive ? "利用中・登録を管理" : "新機能を準備中",
                                            systemImage: "star", showsChevron: false)
                }
                .accessibilityIdentifier("settings.pro")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                NavigationLink {
                    KeyboardGuideView()
                } label: {
                    SettingsDisclosureLabel(title: "nibbleキーボード", detail: "追加・使い方・フルアクセス",
                                            systemImage: "keyboard", showsChevron: false)
                }
                .accessibilityIdentifier("settings.keyboard")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .listRowSeparator(.hidden, edges: .top)
                NavigationLink {
                    DeletedSnippetsView(store: store, effects: effects, onReturn: onTrashReturn)
                } label: {
                    SettingsDisclosureLabel(title: "削除した項目", detail: "復元・完全削除",
                                            systemImage: "trash", showsChevron: false)
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
