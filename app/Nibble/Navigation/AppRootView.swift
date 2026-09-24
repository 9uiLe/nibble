import AppMacros
import SwiftUI
import Observation

@Equatable
struct AppRootView: View {
    private struct VariableCompletion {
        let id = UUID()
        let copyID: UUID
        let values: [String: String]
    }
    private let inputRevision = UUID()
    @State private var library: LibraryModel
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @SkipEquatable private let advertising: any AdvertisingContent
    @State private var routeOwner = LibraryTaskOwner()
    @State private var subscription = ProSubscription()
    @State private var showsSettings = false
    @State private var showsTrash = false
    @State private var variableCompletion: VariableCompletion?
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects,
         advertising: any AdvertisingContent = UnconfiguredAdvertising()) {
        self.store = store
        self.effects = effects
        self.advertising = advertising
        _library = State(initialValue: LibraryModel(store: store, effects: effects))
    }

    var body: some View {
        @Bindable var libraryBinding = library
        NavigationStack {
            LibraryScreen(model: library, searchFocused: $searchFocused,
                          noticesPresented: noticesPresented,
                          advertisement: showsLibraryAd ? advertising.libraryBanner() : nil,
                          openSettings: {
                searchFocused = false
                showsSettings = true
            })
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView(subscription: subscription, showTrash: { showsTrash = true })
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
            SnippetEditor(draft: draft, store: store, proInformation: {
                AnyView(NavigationStack { ProView(subscription: subscription) })
            })
        }
        .sheet(item: Binding(get: { library.variableCopy }, set: { if $0 == nil { library.cancelVariableCopy() } })) { pending in
            VariableFillView(template: pending.template, title: pending.title,
                             actionTitle: "完成文をコピー", compact: false,
                             availability: pending.availability, cancel: { library.cancelVariableCopy() },
                             valueEdited: {},
                             complete: { values in variableCompletion = VariableCompletion(copyID: pending.id, values: values) })
                .id(pending.id)
                .presentationDetents([.height(CGFloat(min(510, 290 + pending.template.names.count * 80))), .large])
        }
        .tint(.nibbleAccent)
        .onChange(of: noticesPresented) { library.setNoticePresentation(noticesPresented) }
        .onChange(of: variableCompletion?.id) {
            if let completion = variableCompletion {
                routeOwner.startTask(.completeVariableCopy(completion.copyID, completion.values), on: library)
                variableCompletion = nil
            }
        }
        .onAppear { library.setNoticePresentation(noticesPresented) }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), library.editor == nil else { return }
            showsTrash = false
            showsSettings = false
            searchFocused = false
            library.showAll()
            library.setNoticePresentation(noticesPresented)
            if route == .create { routeOwner.startTask(.open(.new), on: library) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { routeOwner.endScreen(); library.cancelVariableCopy() }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await subscription.refresh() }
        }
        .task { await subscription.watchUpdates() }
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

    private var showsLibraryAd: Bool {
        noticesPresented && library.variableCopy == nil && !searchFocused && !library.isSearching
            && !FeatureAccess.availability(.adFree, pro: subscription.isActive).isAvailable
    }
}
