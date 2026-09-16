import SwiftUI

struct LibraryView: View {
    private enum TabID: Hashable { case all, pinned, search }

    @State private var selectedTab = TabID.all
    @State private var all = LibraryModel()
    @State private var pinned = LibraryModel(filter: .pinned)
    @State private var search = LibraryModel()
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsTrash = false
    @State private var showsAbout = false
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var searchableLibrary = search
        TabView(selection: $selectedTab) {
            Tab("すべて", systemImage: "tray", value: TabID.all) {
                library(all, title: "すべて", showsDrafts: true)
            }
            Tab("ピン留め", systemImage: "pin", value: TabID.pinned) {
                library(pinned, title: "ピン留め")
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
        .sheet(isPresented: $showsAbout) { AboutView() }
        .tint(.nibbleAccent)
        .onChange(of: selectedTab) {
            if selectedTab != .search { searchFocused = false }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), all.editor == nil,
                  pinned.editor == nil, search.editor == nil else { return }
            showsTrash = false
            showsAbout = false
            searchFocused = false
            search.query = ""
            selectedTab = .all
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
                          searchFocused: $searchFocused,
                          showTrash: { searchFocused = false; showsTrash = true },
                          showAbout: { searchFocused = false; showsAbout = true })
        }
    }

    private var currentLibrary: LibraryModel {
        switch selectedTab {
        case .all: all
        case .pinned: pinned
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
