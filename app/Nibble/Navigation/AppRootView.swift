import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct AppRootView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    private enum TabID: Hashable { case library, settings, search }

    @State private var selectedTab = TabID.library
    @State private var all: LibraryModel
    @State private var search: LibraryModel
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsTrash = false
    @State private var searchPresented = false
    @State private var searchPresentationID = UUID()
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
        // Observe the result in the scene root even when presentation is initially inactive.
        let notice = currentLibrary.notice
        let presentsNotice = noticeOrigin != nil && notice?.origin == noticeOrigin
        tabs
        .background(LibraryNoticeWindow(model: currentLibrary, taskOwner: routeOwner,
                                       isPresented: presentsNotice))
        .tabBarMinimizeBehavior(.onScrollDown)
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
            if selectedTab != .search {
                searchFocused = false
                searchPresented = false
            }
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

    private var tabs: some View {
        @Bindable var searchableLibrary = search
        return TabView(selection: Binding(get: { selectedTab }, set: {
            selectedTab = $0
            searchPresented = $0 == .search
            if $0 == .search { searchPresentationID = UUID() }
            updateNoticePresentation()
        })) {
            Tab(value: TabID.library) {
                library(all, title: "一覧", showsFilters: true)
            } label: {
                TabIcon.library
            }
            .accessibilityLabel("一覧")
            Tab(value: TabID.settings) {
                NavigationStack {
                    SettingsView(showTrash: {
                        showsTrash = true
                        updateNoticePresentation()
                    })
                }
                .environment(\.illustrationPlaybackAllowed,
                             selectedTab == .settings && !showsTrash && all.editor == nil && search.editor == nil)
            } label: {
                TabIcon.settings
            }
            .accessibilityLabel("設定")
            Tab(value: TabID.search) {
                NavigationStack {
                    LibraryScreen(model: search, title: "検索", showsFilters: false, showsSearchPrompt: true,
                                  searchFocused: $searchFocused)
                        .searchable(text: $searchableLibrary.query, isPresented: $searchPresented,
                                    placement: .toolbar,
                                    prompt: "タイトルや本文を検索")
                        .searchFocused($searchFocused)
                        .searchPresentationToolbarBehavior(.avoidHidingContent)
                        .toolbar {
                            DefaultToolbarItem(kind: .search, placement: .bottomBar)
                        }
                        .toolbar(searchPresented ? .visible : .hidden, for: .bottomBar)
                        .toolbar(searchPresented ? .hidden : .visible, for: .tabBar)
                        .onChange(of: searchPresented) { searchFocused = searchPresented }
                        .onAppear {
                            searchPresented = true
                            searchFocused = true
                        }
                }
                // Reenter the native search presentation while the root model keeps its query and results.
                .id(searchPresentationID)
            } label: {
                TabIcon.search
            }
            .accessibilityLabel("検索")
        }
        .modifier(LibraryResultFeedback(all: all, search: search))
    }

    private func library(_ model: LibraryModel, title: String, showsFilters: Bool = false) -> some View {
        NavigationStack {
            LibraryScreen(model: model, title: title, showsFilters: showsFilters,
                          searchFocused: $searchFocused)
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

/// Keeps success feedback tied to completed operations rather than notice appearances.
private struct LibraryResultFeedback: ViewModifier {
    let all: LibraryModel
    let search: LibraryModel

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: all.feedback)
            .sensoryFeedback(.success, trigger: search.feedback)
    }
}
