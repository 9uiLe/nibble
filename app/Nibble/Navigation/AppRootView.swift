import AppMacros
import SwiftUI
import Observation

@Equatable
struct AppRootView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @State private var selectedTab = AppTab.library
    @State private var library: LibraryModel
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
        _library = State(initialValue: LibraryModel(store: store, effects: effects))
        let search = LibraryModel(store: store, effects: effects, surface: .search)
        search.setNoticePresentation(false)
        _search = State(initialValue: search)
    }

    var body: some View {
        @Bindable var libraryBinding = library
        @Bindable var searchableLibrary = search
        TabView(selection: $selectedTab) {
            Tab("一覧", systemImage: "house", value: AppTab.library) {
                NavigationStack {
                    LibraryScreen(model: library, searchFocused: $searchFocused)
                        .modifier(LibraryNoticeOverlay(model: library, taskOwner: routeOwner,
                                                       isPresented: noticeOrigin == .library))
                }
            }
            .accessibilityIdentifier("navigation.tab.library")
            Tab("検索", systemImage: "magnifyingglass", value: AppTab.search) {
                NavigationStack {
                    LibraryScreen(model: search,
                                  searchFocused: $searchFocused)
                        .modifier(LibraryNoticeOverlay(model: search, taskOwner: routeOwner,
                                                       isPresented: noticeOrigin == .search))
                }
                .toolbar(searchFocused ? .hidden : .visible, for: .tabBar)
            }
            .accessibilityIdentifier("navigation.tab.search")
            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(library: library, showTrash: {
                        showsTrash = true
                        updateNoticePresentation()
                    })
                }
                .environment(\.illustrationPlaybackAllowed,
                             selectedTab == .settings && !showsTrash && library.editor == nil && search.editor == nil)
            }
            .accessibilityIdentifier("navigation.tab.settings")
        }
        .modifier(LibraryResultFeedback(library: library, search: search))
        .tabBarMinimizeBehavior(.never)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sheet(isPresented: $showsTrash, onDismiss: {
            routeOwner.startTask(.refresh, on: library)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) {
            DeletedSnippetsView(store: store, effects: effects)
        }
        // Scene presentations outlive the system tab's content during background transitions.
        .sheet(item: $libraryBinding.editor, onDismiss: {
            routeOwner.startTask(.refresh, on: library)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .sheet(item: $searchableLibrary.editor, onDismiss: {
            routeOwner.startTask(.refresh, on: library)
            searchRefreshOwner.startTask(.refresh, on: search)
        }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .tint(.nibbleAccent)
        .onChange(of: library.mutationRevision) { searchRefreshOwner.startTask(.refresh, on: search) }
        .onChange(of: search.mutationRevision) { routeOwner.startTask(.refresh, on: library) }
        .onChange(of: selectedTab) {
            updateNoticePresentation()
            if selectedTab != .search { searchFocused = false }
        }
        .onChange(of: showsTrash) { updateNoticePresentation() }
        .onChange(of: library.editor?.id) { updateNoticePresentation() }
        .onChange(of: search.editor?.id) { updateNoticePresentation() }
        .onAppear { updateNoticePresentation() }
        // Scene phase, tab and sheet state own notice eligibility.
        // SwiftUI can remount this root without ending the visible scene.
        .onOpenURL { url in
            guard let route = AppRoute(url: url), library.editor == nil,
                  search.editor == nil else { return }
            showsTrash = false
            searchFocused = false
            search.query = ""
            library.filter = .all
            selectedTab = .library
            updateNoticePresentation()
            if route == .create { routeOwner.startTask(.open(.new), on: library) }
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
        guard scenePhase == .active, !showsTrash, library.editor == nil, search.editor == nil else { return nil }
        switch selectedTab {
        case .library: return .library
        case .search: return .search
        case .settings: return nil
        }
    }

    private func updateNoticePresentation() {
        library.setNoticePresentation(noticeOrigin == .library)
        search.setNoticePresentation(noticeOrigin == .search)
    }
}
