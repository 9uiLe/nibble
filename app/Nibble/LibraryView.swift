import SwiftUI

struct LibraryView: View {
    private enum TabID: Hashable { case library, settings, search }

    @State private var selectedTab = TabID.library
    @AppStorage(ActionButtonSide.storageKey) private var actionButtonSide = ActionButtonSide.right
    @State private var all = LibraryModel()
    @State private var search = LibraryModel()
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsTrash = false
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var searchableLibrary = search
        TabView(selection: $selectedTab) {
            Tab("一覧", systemImage: "list.bullet", value: TabID.library) {
                library(all, title: "一覧", showsDrafts: true)
            }
            Tab("設定", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    LibrarySettingsView(actionButtonSide: $actionButtonSide, showTrash: { showsTrash = true })
                }
            }
            Tab("検索", systemImage: "magnifyingglass", value: TabID.search, role: .search) {
                library(search, title: "検索")
                    .searchable(text: $searchableLibrary.query, prompt: "タイトルや本文を検索")
                    .searchFocused($searchFocused)
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.never)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sheet(isPresented: $showsTrash, onDismiss: { routeOwner.startTask(.refresh, on: currentLibrary) }) {
            DeletedSnippetsView()
        }
        .tint(.nibbleAccent)
        .onChange(of: selectedTab) {
            if selectedTab != .search { searchFocused = false }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), all.editor == nil,
                  search.editor == nil else { return }
            showsTrash = false
            searchFocused = false
            search.query = ""
            selectedTab = .library
            if route == .create { routeOwner.startTask(.open(.new), on: all) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { routeOwner.endScreen() }
        }
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Color.nibbleCanvas.ignoresSafeArea().overlay {
                    Text("nibble").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.nibbleAccent)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func library(_ model: LibraryModel, title: String, showsDrafts: Bool = false) -> some View {
        NavigationStack {
            LibraryScreen(model: model, title: title, showsDrafts: showsDrafts,
                          searchFocused: $searchFocused, actionButtonSide: actionButtonSide)
        }
    }

    private var currentLibrary: LibraryModel {
        switch selectedTab {
        case .library, .settings: all
        case .search: search
        }
    }
}

private struct DeletedSnippetsView: View {
    @State private var model = LibraryModel(filter: .trash)
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var library = model
        NavigationStack {
            LibraryScreen(model: model, title: "削除した項目", showsDrafts: false,
                          searchFocused: $searchFocused)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる", systemImage: "xmark") { dismiss() }
                            .accessibilityIdentifier("library.trash.close")
                    }
                }
        }
        .searchable(text: $library.query, prompt: "削除した項目を検索")
        .searchFocused($searchFocused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
    }
}

/// Root screens keep their heading in the navigation bar while content scrolls.
struct LibraryNavigationTitle: ViewModifier {
    let title: String
    var leading = true

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: leading ? .title : nil)
            .toolbar {
                if leading {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("navigation.title")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}
