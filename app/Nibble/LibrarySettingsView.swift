import AppMacros
import SwiftUI

enum ActionButtonSide: String, CaseIterable, Identifiable {
    case left, right
    static let storageKey = "library.actionButtonSide"
    var id: Self { self }
    var title: String { self == .left ? "左側" : "右側" }
}

@Equatable
struct LibrarySettingsView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @Binding var actionButtonSide: ActionButtonSide
    let showTrash: () -> Void

    var body: some View {
        List {
            Group {
                Section {
                    Picker("操作ボタンの位置", selection: $actionButtonSide) {
                        ForEach(ActionButtonSide.allCases) { side in
                            Text(side.title).tag(side)
                                .accessibilityIdentifier("settings.side.\(side.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.actionButtonSide")
                } header: {
                    Text("操作ボタンの位置")
                } footer: {
                    Text("新しく作るボタンと、各項目のコピーボタンの位置を変えます。")
                }
                Section("保存した項目") {
                    Button("削除した項目", systemImage: "trash", action: showTrash)
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
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.nibbleCanvas)
        .modifier(LibraryNavigationTitle(title: "設定"))
    }
}
