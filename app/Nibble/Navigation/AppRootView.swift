import AppMacros
import SwiftUI
import Observation
import ScopedAnimation
import UIKit

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
    @State private var tabScroll = TabBarScrollState()
    @State private var searchVisit = UUID()
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
        .toolbar(.hidden, for: .tabBar)
        .environment(\.tabBarScrollState, tabScroll)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !searchFocused { tabBar }
        }
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

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("一覧", systemImage: "house", value: TabID.library) {
                library(all, title: "一覧", showsFilters: true)
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab("検索", systemImage: "magnifyingglass", value: TabID.search) {
                NavigationStack {
                    LibraryScreen(model: search, title: "検索", showsFilters: false, showsSearchPrompt: true,
                                  searchFocused: $searchFocused)
                }
                .background {
                    SearchFocusOnAppearance(focus: $searchFocused)
                        .id(searchVisit)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
                .toolbar(.hidden, for: .tabBar)
            }
            Tab("設定", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    SettingsView(showTrash: {
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
    }

    private var tabBar: some View {
        AnimationScope(.smooth(duration: 0.24), value: tabScroll.isCompact, name: "Navigation.TabBar") {
            HStack(spacing: 0) {
                navigationButton(.library, title: "一覧", symbol: selectedTab == .library ? "house.fill" : "house")
                navigationButton(.search, title: "検索", symbol: "magnifyingglass")
                Button {
                    searchFocused = false
                    routeOwner.startTask(.open(.new), on: currentLibrary)
                } label: {
                    TabIcon(symbol: "plus", size: tabScroll.isCompact ? 23 : 28)
                        .frame(maxWidth: .infinity)
                        .frame(height: tabScroll.isCompact ? 44 : 52)
                        .contentShape(.capsule)
                }
                .accessibilityLabel("新規作成")
                .accessibilityHint("編集画面を開きます")
                .accessibilityIdentifier("library.add")
                .keyboardShortcut("n", modifiers: .command)
                navigationButton(.settings, title: "設定", symbol: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(tabScroll.isCompact ? 2 : 4)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, tabScroll.isCompact ? 52 : 22)
            .frame(maxWidth: 560)
        }
        // Keep the content viewport stable while only the floating bar changes size.
        .frame(maxWidth: .infinity)
        .frame(height: 68, alignment: .bottom)
        .padding(.bottom, 8)
    }

    private func navigationButton(_ tab: TabID, title: String, symbol: String) -> some View {
        Button {
            let reselectsSearch = selectedTab == .search && tab == .search
            if tab == .search && !reselectsSearch { searchVisit = UUID() }
            selectedTab = tab
            tabScroll.expand()
            if reselectsSearch { searchFocused = true }
        } label: {
            TabIcon(symbol: symbol, size: tabScroll.isCompact ? 22 : 27)
                .frame(maxWidth: .infinity)
                .frame(height: tabScroll.isCompact ? 44 : 52)
                .background(selectedTab == tab ? Color.primary.opacity(0.09) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTab == tab ? "選択中" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("navigation.tab.\(tab)")
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

/// Native tab transitions can clear an earlier SwiftUI focus request.
/// Each search visit requests focus once, after the containing tab is visible.
@Equatable(.mainActor)
private struct SearchFocusOnAppearance: UIViewControllerRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let focus: FocusState<Bool>.Binding

    func makeUIViewController(context: Context) -> SearchFocusController {
        SearchFocusController(focus: focus)
    }

    func updateUIViewController(_ controller: SearchFocusController, context: Context) {
        controller.focus = focus
    }
}

private final class SearchFocusController: UIViewController {
    var focus: FocusState<Bool>.Binding
    private var hasRequestedFocus = false

    init(focus: FocusState<Bool>.Binding) {
        self.focus = focus
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasRequestedFocus else { return }
        hasRequestedFocus = true
        focus.wrappedValue = true
    }
}

/// Only deliberate scrolling changes the bar; reloads, keyboard layout and bounce do not.
@MainActor
@Observable
final class TabBarScrollState {
    private(set) var isCompact = false
    @ObservationIgnored private var travel = 0
    @ObservationIgnored private var gestureDirection = 0

    func expand() {
        isCompact = false
        travel = 0
    }

    func beginGesture() {
        travel = 0
        gestureDirection = 0
    }

    func observe(from old: Int, to new: Int, phase: ScrollPhase) {
        guard phase == .interacting || phase == .decelerating else { return }
        let delta = new - old
        guard delta != 0 else { return }
        let direction = delta > 0 ? 1 : -1
        // Rubber-band settling reverses geometry without a new user gesture.
        if phase == .decelerating && direction != gestureDirection { return }
        gestureDirection = direction
        if new == 0 { expand(); return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel >= 24 { isCompact = true }
        else if travel <= -16 { isCompact = false }
    }
}

extension EnvironmentValues {
    @Entry var tabBarScrollState: TabBarScrollState?
}

struct TabBarScrollTracking: ViewModifier {
    var enabled = true
    @Environment(\.tabBarScrollState) private var tabScroll
    @State private var phase = ScrollPhase.idle

    func body(content: Content) -> some View {
        content
            // TabView hosts do not pass the root's custom bar inset into every scroll view.
            // Keep the final row/paragraph reachable above the bar at either size.
            .contentMargins(.bottom, enabled ? 76 : 0, for: .scrollContent)
            .onScrollPhaseChange { _, next in
                phase = next
                if next == .interacting { tabScroll?.beginGesture() }
            }
            .onScrollGeometryChange(for: Int.self) { geometry in
                let maximum = max(0, geometry.contentSize.height + geometry.contentInsets.top
                                  + geometry.contentInsets.bottom - geometry.containerSize.height)
                return Int(max(0, min(maximum, geometry.contentOffset.y + geometry.contentInsets.top)))
            } action: { old, new in
                if enabled {
                    tabScroll?.observe(from: old, to: new, phase: phase)
                }
            }
            .onAppear { if enabled { tabScroll?.expand() } }
    }
}
