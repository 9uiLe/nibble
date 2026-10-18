import AppMacros
import SwiftUI

@MainActor @Equatable
struct AppRootView: View {
    private struct Completion {
        let id = UUID()
        let request: UUID
        let values: [VariableName: String]
    }
    private let inputRevision = UUID()
    @SkipEquatable private let store: any LibraryStorage & DraftEditing
    @SkipEquatable private let effects: any LibraryEffects
    @State private var library: LibraryModel
    @State private var owner = LibraryTaskOwner()
    @State private var subscription = ProSubscription()
    @State private var settings = false
    @State private var completion: Completion?
    @State private var trashChanged = UUID()
    @FocusState private var searching: Bool
    @Environment(\.scenePhase) private var phase
    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects) {
        self.store = store; self.effects = effects
        _library = State(initialValue: LibraryModel(store: store, effects: effects, proIsActive: ProAccess.isActive))
    }
    private var acceptsNotices: Bool { phase == .active && !settings && library.editor == nil }
    var body: some View {
        @Bindable var bindable = library
        NavigationStack {
            LibraryScreen(model: library, searchFocused: $searching, noticesPresented: acceptsNotices && library.variableCopy == nil) {
                searching = false
                settings = true
            }
            .navigationDestination(isPresented: $settings) {
                SettingsView(subscription: subscription, store: store, effects: effects) { trashChanged = UUID() }
                    .environment(\.illustrationPlaybackAllowed, library.editor == nil)
            }
        }
        .sheet(item: $bindable.editor, onDismiss: { owner.startTask(.reload, on: library) }) { draft in
            SnippetEditor(draft: draft, store: store, proIsActive: ProAccess.isActive, proInformation: {
                AnyView(NavigationStack { ProView(subscription: subscription) })
            })
        }
        .sheet(item: Binding(get: { library.variableCopy }, set: { if $0 == nil { library.cancelVariableCopy() } })) { request in
            NavigationStack {
                VariableFillView(template: request.template, title: request.title, actionTitle: "完成文をコピー", compact: false,
                                 availability: request.availability, cancel: { library.cancelVariableCopy() },
                                 complete: { completion = Completion(request: request.id, values: $0) })
                    .navigationTitle("値を入力").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") { library.cancelVariableCopy() }.accessibilityLabel("確定せず閉じる").accessibilityIdentifier("variables.cancel")
                        }
                    }
            }
            .id(request.id).presentationDetents([.height(CGFloat(min(510, 290 + 80 * request.template.names.count))), .large])
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: completion?.id) {
            if let completion { owner.startTask(.completeVariableCopy(completion.request, completion.values), on: library) }
            completion = nil
        }
        .onChange(of: trashChanged) { owner.startTask(.reload, on: library) }
        .onChange(of: acceptsNotices, initial: true) { library.setNoticePresentation(acceptsNotices) }
        .onChange(of: phase) { if phase == .background { owner.endScreen(); library.cancelVariableCopy() } }
        .onOpenURL { url in
            guard let route = AppRoute(url: url), library.editor == nil else { return }
            settings = false
            searching = false
            library.showAll()
            if route == .create { owner.startTask(.open(.new), on: library) }
        }
        .onSubmit(of: .search) { searching = false }
        .task(id: phase) { if phase == .active { await subscription.refresh() } }
        .task { await subscription.watchUpdates() }
        .sensoryFeedback(.success, trigger: library.feedback)
        .tint(Color.nibbleAccent).privacySensitive()
        .overlay {
            if phase != .active {
                ZStack { Color.nibbleCanvas.ignoresSafeArea(); Text("nibble").font(.nibbleScreenTitle) }.accessibilityHidden(true)
            }
        }
    }
}
