import AppMacros
import SwiftUI
import Observation

@Equatable
struct AppRootView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @State private var selectedTab = AppTab.library
    @State private var all: LibraryModel
    @State private var search: LibraryModel
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @State private var routeOwner = LibraryTaskOwner()
    @State private var searchRefreshOwner = LibraryTaskOwner()
    @State private var showsTrash = false
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        self.store = store
        self.effects = effects
        _all = State(initialValue: LibraryModel(store: store, effects: effects, retainsFilters: true))
        let search = LibraryModel(store: store, effects: effects, noticeOrigin: .search)
        search.setNoticePresentation(false)
        _search = State(initialValue: search)
    }

    var body: some View {
        @Bindable var allLibrary = all
        @Bindable var searchableLibrary = search
        TabView(selection: $selectedTab) {
            Tab("一覧", systemImage: "house", value: AppTab.library) {
                NavigationStack {
                    LibraryScreen(model: all, surface: .library, searchFocused: $searchFocused)
                        .modifier(LibraryNoticeOverlay(model: all, taskOwner: routeOwner,
                                                       isPresented: noticeOrigin == .library))
                }
            }
            .accessibilityIdentifier("navigation.tab.library")
            Tab("検索", systemImage: "magnifyingglass", value: AppTab.search) {
                NavigationStack {
                    LibraryScreen(model: search, surface: .search,
                                  searchFocused: $searchFocused)
                        .modifier(LibraryNoticeOverlay(model: search, taskOwner: routeOwner,
                                                       isPresented: noticeOrigin == .search))
                }
                .toolbar(searchFocused ? .hidden : .visible, for: .tabBar)
            }
            .accessibilityIdentifier("navigation.tab.search")
            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(library: all, showTrash: {
                        showsTrash = true
                        updateNoticePresentation()
                    })
                }
                .environment(\.illustrationPlaybackAllowed,
                             selectedTab == .settings && !showsTrash && all.editor == nil && search.editor == nil)
            }
            .accessibilityIdentifier("navigation.tab.settings")
        }
        .modifier(LibraryResultFeedback(all: all, search: search))
        .tabBarMinimizeBehavior(.never)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sheet(isPresented: $showsTrash, onDismiss: {
            routeOwner.startTask(.refresh, on: all)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) {
            DeletedSnippetsView(store: store, effects: effects)
        }
        // Scene presentations outlive the system tab's content during background transitions.
        .sheet(item: $allLibrary.editor, onDismiss: {
            routeOwner.startTask(.refresh, on: all)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .sheet(item: $searchableLibrary.editor, onDismiss: {
            routeOwner.startTask(.refresh, on: all)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .tint(.nibbleAccent)
        .onChange(of: all.mutationRevision) { searchRefreshOwner.startTask(.refresh, on: search) }
        .onChange(of: search.mutationRevision) { routeOwner.startTask(.refresh, on: all) }
        .onChange(of: selectedTab) {
            updateNoticePresentation()
            if selectedTab != .search { searchFocused = false }
        }
        .onChange(of: showsTrash) { updateNoticePresentation() }
        .onChange(of: all.editor?.id) { updateNoticePresentation() }
        .onChange(of: search.editor?.id) { updateNoticePresentation() }
        .onAppear { updateNoticePresentation() }
        // Scene phase, tab and sheet state own notice eligibility.
        // SwiftUI can remount this root without ending the visible scene.
        .onOpenURL { url in
            guard let route = AppRoute(url: url), all.editor == nil,
                  search.editor == nil else { return }
            showsTrash = false
            searchFocused = false
            search.query = ""
            all.filter = .all
            selectedTab = .library
            updateNoticePresentation()
            if route == .create { routeOwner.startTask(.open(.new), on: all) }
        }
        .onChange(of: scenePhase) {
            updateNoticePresentation()
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

    private var noticeOrigin: LibraryModel.Notice.Origin? {
        guard scenePhase == .active, !showsTrash, all.editor == nil, search.editor == nil else { return nil }
        switch selectedTab {
        case .library: return .library
        case .search: return .search
        case .settings: return nil
        }
    }

    private func updateNoticePresentation() {
        all.setNoticePresentation(noticeOrigin == .library)
        search.setNoticePresentation(noticeOrigin == .search)
    }
}
