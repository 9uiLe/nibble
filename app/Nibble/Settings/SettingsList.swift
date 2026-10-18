import AppMacros
import SwiftUI

@MainActor @Equatable
struct SettingsList: View {
    private let inputRevision = UUID()
    let version: AppVersion
    @SkipEquatable let subscription: ProSubscription
    @SkipEquatable let store: any LibraryStorage & DraftEditing
    @SkipEquatable let effects: any LibraryEffects
    @SkipEquatable let onTrashReturn: () -> Void
    var body: some View {
        List {
            NavigationLink {
                KeyboardGuideView()
            } label: {
                SettingsDisclosureLabel(title: "nibbleキーボード", detail: "追加・使い方・フルアクセス", systemImage: "keyboard")
            }.accessibilityIdentifier("settings.keyboard")
            NavigationLink {
                DeletedSnippetsView(store: store, effects: effects, onReturn: onTrashReturn)
            } label: {
                SettingsDisclosureLabel(title: "削除した項目", detail: "復元・完全削除", systemImage: "trash")
            }.accessibilityIdentifier("library.trash")
            NavigationLink {
                ProView(subscription: subscription)
            } label: {
                SettingsDisclosureLabel(title: "nibble Pro", detail: subscription.isActive ? "利用中・登録を管理" : "新機能を準備中", systemImage: "star")
            }.accessibilityIdentifier("settings.pro")
            NavigationLink {
                AboutView()
            } label: {
                SettingsDisclosureLabel(title: "nibbleについて", detail: "操作とデータについて", systemImage: "info.circle")
            }.accessibilityIdentifier("settings.about").listRowSeparator(.hidden, edges: .bottom)
            Text("バージョン \(version.display)").font(.footnote).foregroundStyle(Color.nibbleSecondary)
                .frame(maxWidth: .infinity).padding(.top, 16)
                .listRowSeparator(.hidden).accessibilityIdentifier("settings.version")
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Color.nibbleCanvas)
        .foregroundStyle(Color.nibblePrimary)
    }
}
