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
    @State private var showsTrash = false
    @State private var tabScroll = TabBarScrollState()
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        self.store = store
        self.effects = effects
        _all = State(initialValue: LibraryModel(store: store, effects: effects))
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
                }
                .toolbar(.hidden, for: .tabBar)
            }
            Tab("検索", systemImage: "magnifyingglass", value: AppTab.search) {
                NavigationStack {
                    LibraryScreen(model: search, surface: .search,
                                  searchFocused: $searchFocused)
                }
                .toolbar(.hidden, for: .tabBar)
            }
            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(library: all, showTrash: {
                        showsTrash = true
                        updateNoticePresentation()
                    })
                }
                .toolbar(.hidden, for: .tabBar)
                .environment(\.illustrationPlaybackAllowed,
                             selectedTab == .settings && !showsTrash && all.editor == nil && search.editor == nil)
            }
        }
        .modifier(LibraryResultFeedback(all: all, search: search))
        .modifier(LibraryNoticeOverlay(model: currentLibrary, taskOwner: routeOwner,
                                       isPresented: noticeOrigin != nil))
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !searchFocused { FloatingTabBar(selection: $selectedTab) }
        }
        .environment(\.tabBarScrollState, tabScroll)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sheet(isPresented: $showsTrash, onDismiss: { routeOwner.startTask(.refresh, on: currentLibrary) }) {
            DeletedSnippetsView(store: store, effects: effects)
        }
        // Scene presentations outlive the system tab's content during background transitions.
        .sheet(item: $allLibrary.editor, onDismiss: { routeOwner.startTask(.refresh, on: all) }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .sheet(item: $searchableLibrary.editor, onDismiss: { routeOwner.startTask(.refresh, on: search) }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .tint(.nibbleAccent)
        .onChange(of: selectedTab) {
            updateNoticePresentation()
            tabScroll.expand()
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

    private var currentLibrary: LibraryModel {
        switch selectedTab {
        case .library, .settings: all
        case .search: search
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
