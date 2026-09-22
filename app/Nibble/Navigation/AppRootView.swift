import AppMacros
import SwiftUI
import Observation

@Equatable
struct AppRootView: View {
    private let inputRevision = UUID()
    @State private var library: LibraryModel
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @State private var routeOwner = LibraryTaskOwner()
    @State private var showsSettings = false
    @State private var showsTrash = false
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        self.store = store
        self.effects = effects
        _library = State(initialValue: LibraryModel(store: store, effects: effects))
    }

    var body: some View {
        @Bindable var libraryBinding = library
        NavigationStack {
            LibraryScreen(model: library, searchFocused: $searchFocused,
                          noticesPresented: noticesPresented, openSettings: {
                searchFocused = false
                showsSettings = true
            })
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView(library: library, showTrash: { showsTrash = true })
                    .environment(\.illustrationPlaybackAllowed,
                                 showsSettings && !showsTrash && library.editor == nil)
            }
        }
        .sensoryFeedback(.success, trigger: library.feedback)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sheet(isPresented: $showsTrash, onDismiss: {
            routeOwner.startTask(.reload, on: library)
        }) {
            DeletedSnippetsView(store: store, effects: effects)
        }
        .sheet(item: $libraryBinding.editor, onDismiss: {
            routeOwner.startTask(.reload, on: library)
        }) { draft in
            SnippetEditor(draft: draft, store: store)
        }
        .tint(.nibbleAccent)
        .onChange(of: noticesPresented) { library.setNoticePresentation(noticesPresented) }
        .onAppear { library.setNoticePresentation(noticesPresented) }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), library.editor == nil else { return }
            showsTrash = false
            showsSettings = false
            searchFocused = false
            library.query = ""
            library.filter = .all
            library.setNoticePresentation(noticesPresented)
            if route == .create { routeOwner.startTask(.open(.new), on: library) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { routeOwner.endScreen() }
        }
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Color.nibbleCanvas.ignoresSafeArea().overlay {
                    Text("nibble").font(.nibbleScreenTitle).foregroundStyle(Color.nibbleAccent)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private var noticesPresented: Bool {
        scenePhase == .active && !showsSettings && !showsTrash && library.editor == nil
    }
}
