import AppMacros
import SwiftUI

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
    @State private var notifications: LibraryNotifications
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsTrash = false
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        self.store = store
        self.effects = effects
        let notifications = LibraryNotifications(effects: effects)
        _notifications = State(initialValue: notifications)
        _all = State(initialValue: LibraryModel(store: store, effects: effects, notifications: notifications, notificationSource: .library))
        _search = State(initialValue: LibraryModel(store: store, effects: effects, notifications: notifications, notificationSource: .search))
    }

    var body: some View {
        tabs
        .modifier(LibraryAccessoryPlacement(notifications: notifications, enabled: activeNoticeTab != nil && notifications.notice != nil, all: all, search: search, taskOwner: routeOwner))
        .sensoryFeedback(.success, trigger: notifications.feedback)
        .onChange(of: activeNoticeTab, initial: true) { notifications.activate(activeNoticeTab) }
        .onDisappear { notifications.activate(nil) }
    }

    private var tabs: some View {
        @Bindable var allLibrary = all
        @Bindable var searchableLibrary = search
        return TabView(selection: Binding(get: { selectedTab }, set: { value in
            selectedTab = value
            notifications.activate(activeNoticeTab)
        })) {
            Tab("一覧", systemImage: "list.bullet", value: TabID.library) {
                library(all, title: "一覧", tab: .library, showsFilters: true)
            }
            Tab("設定", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    LibrarySettingsView(actionButtonSide: $actionButtonSide, showTrash: { showsTrash = true })
                }
            }
            Tab("検索", systemImage: "magnifyingglass", value: TabID.search, role: .search) {
                library(search, title: "検索", tab: .search, showsSearchPrompt: true)
                    .searchable(text: $searchableLibrary.query, prompt: "タイトルや本文を検索")
                    .searchFocused($searchFocused)
                    .searchPresentationToolbarBehavior(.avoidHidingContent)
            }
        }
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
            if selectedTab != .search { searchFocused = false }
        }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), all.editor == nil,
                  search.editor == nil else { return }
            showsTrash = false
            searchFocused = false
            search.query = ""
            all.filter = .all
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

    private func library(_ model: LibraryModel, title: String, tab: LibraryNotifications.SourceTab, showsFilters: Bool = false, showsSearchPrompt: Bool = false) -> some View {
        NavigationStack {
            LibraryScreen(model: model, title: title, showsFilters: showsFilters,
                          showsSearchPrompt: showsSearchPrompt, showsInlineNotice: false, searchFocused: $searchFocused, actionButtonSide: actionButtonSide)
                .background { legacyAccessory(for: tab) }
        }
    }

    private var activeNoticeTab: LibraryNotifications.SourceTab? {
        guard scenePhase == .active, !showsTrash, all.editor == nil, search.editor == nil else { return nil }
        switch selectedTab {
        case .library: return .library
        case .search: return .search
        case .settings: return nil
        }
    }

    @ViewBuilder
    private func legacyAccessory(for tab: LibraryNotifications.SourceTab) -> some View {
        if #available(iOS 26.1, *) { EmptyView() }
        else {
            LegacyLibraryAccessory(notifications: notifications,
                                   isEnabled: activeNoticeTab == tab && notifications.notice != nil, all: all, search: search, taskOwner: routeOwner)
                .frame(width: 0, height: 0)
        }
    }

    private var currentLibrary: LibraryModel {
        switch selectedTab {
        case .library, .settings: all
        case .search: search
        }
    }
}

@Equatable
private struct DeletedSnippetsView: View {
    @State private var model: LibraryModel
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

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

/// OS availability is fixed for the scene; notice changes do not replace the tabs.
private struct LibraryAccessoryPlacement: ViewModifier {
    let notifications: LibraryNotifications
    let enabled: Bool
    let all: LibraryModel
    let search: LibraryModel
    let taskOwner: LibraryTaskOwner

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) {
                LibraryAccessory(notifications: notifications, all: all, search: search, taskOwner: taskOwner)
            }
        } else { content }
    }
}
