import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct LibraryView: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    private enum TabID: Hashable { case library, settings, search }

    @State private var selectedTab = TabID.library
    @AppStorage(ActionButtonSide.storageKey) private var actionButtonSide = ActionButtonSide.right
    @State private var all: LibraryModel
    @State private var search: LibraryModel
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsTrash = false
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
        TabView(selection: Binding(get: { selectedTab }, set: {
            selectedTab = $0
            updateNoticePresentation()
        })) {
            Tab("一覧", systemImage: "list.bullet", value: TabID.library) {
                library(all, title: "一覧", showsFilters: true)
            }
            Tab("設定", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    LibrarySettingsView(actionButtonSide: $actionButtonSide, showTrash: {
                        showsTrash = true
                        updateNoticePresentation()
                    })
                }
            }
            Tab("検索", systemImage: "magnifyingglass", value: TabID.search, role: .search) {
                library(search, title: "検索", showsSearchPrompt: true)
                    .searchable(text: $searchableLibrary.query, prompt: "タイトルや本文を検索")
                    .searchFocused($searchFocused)
                    .searchPresentationToolbarBehavior(.avoidHidingContent)
            }
        }
        .modifier(LibraryTabAccessory(all: all, search: search, origin: noticeOrigin, searchFocused: searchFocused, taskOwner: routeOwner))
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.never)
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
            if selectedTab != .search { searchFocused = false }
        }
        .onChange(of: showsTrash) { updateNoticePresentation() }
        .onChange(of: all.editor?.id) { updateNoticePresentation() }
        .onChange(of: search.editor?.id) { updateNoticePresentation() }
        .onAppear { updateNoticePresentation() }
        .onDisappear {
            all.setNoticePresentation(false)
            search.setNoticePresentation(false)
        }
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

    private func library(_ model: LibraryModel, title: String, showsFilters: Bool = false, showsSearchPrompt: Bool = false) -> some View {
        NavigationStack {
            LibraryScreen(model: model, title: title, showsFilters: showsFilters,
                          showsSearchPrompt: showsSearchPrompt, searchFocused: $searchFocused, actionButtonSide: actionButtonSide)
                .safeAreaBar(edge: .top) {
                    if showsSearchPrompt, searchFocused, noticeOrigin == .search, search.notice != nil {
                        LibraryAccessoryContent(model: search, taskOwner: routeOwner)
                            .frame(minHeight: 48)
                    }
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

/// Only the accessory observes transient result content. The tab hierarchy keeps its identity.
private struct LibraryTabAccessory: ViewModifier {
    let all: LibraryModel
    let search: LibraryModel
    let origin: LibraryModel.Notice.Origin?
    let searchFocused: Bool
    let taskOwner: LibraryTaskOwner

    private var model: LibraryModel? {
        switch origin {
        case .library: all
        case .search: searchFocused ? nil : search
        default: nil
        }
    }

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled: model?.notice != nil) { accessory }
            } else {
                // 26.0 removes the accessory when the builder has no content.
                // Branch inside the accessory, never around the TabView.
                content.tabViewBottomAccessory { accessory }
            }
        }
        .sensoryFeedback(.success, trigger: all.feedback)
        .sensoryFeedback(.success, trigger: search.feedback)
    }

    @ViewBuilder private var accessory: some View {
        if let model, model.notice != nil {
            LibraryAccessoryContent(model: model, taskOwner: taskOwner)
                .animationBarrier(warnsOnLeaks: false)
        }
    }
}

@Equatable
private struct LibraryAccessoryContent: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner

    var body: some View {
        LibraryNotice(model: model, restore: { taskOwner.startTask(.undoNotice($0), on: model) }, inAccessory: true)
    }
}

@Equatable
private struct DeletedSnippetsView: View {
    @State private var model: LibraryModel
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        _model = State(initialValue: LibraryModel(store: store, effects: effects, filter: .trash))
    }

    var body: some View {
        @Bindable var library = model
        NavigationStack {
            LibraryScreen(model: model, title: "削除した項目", showsFilters: false,
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
        .sensoryFeedback(.success, trigger: model.feedback)
        .onAppear { model.setNoticePresentation(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setNoticePresentation(scenePhase == .active) }
        .onDisappear { model.setNoticePresentation(false) }
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
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("navigation.title")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}
