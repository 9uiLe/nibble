import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct LibraryScreen: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @SkipEquatable let model: LibraryModel
    private var surface: LibrarySurface { model.surface }
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    var noticesPresented = false
    @SkipEquatable let advertisement: AnyView?
    var openSettings: () -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?

    var body: some View {
        @Bindable var library = model
        VStack(spacing: 0) {
            if surface.isRoot {
                RootScreenHeading(openSettings: openSettings)
            }
            if surface.isRoot { LibrarySearchBar(model: model, searchFocused: searchFocused) }
            if surface.showsFilters && !model.isSearching {
                LibraryFilterBar(selection: $library.filter, counts: model.snapshot?.page.counts)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LibraryList(model: model, taskOwner: taskOwner, searchFocused: searchFocused,
                        permanentDeletion: $permanentDeletion)
                .modifier(LibraryNoticeOverlay(model: model, taskOwner: taskOwner,
                                               isPresented: noticesPresented))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if surface.isRoot && !searchFocused.wrappedValue {
                VStack(spacing: 0) {
                    if let advertisement { advertisement }
                    CreateSnippetButton(model: model, prominent: true)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .overlay(alignment: .top) { Divider() }
                }
                .background(Color.nibbleCanvas)
            }
        }
        .background(Color.nibbleCanvas)
        .navigationTitle(surface.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar(surface.isRoot ? .hidden : .visible, for: .navigationBar)
        .confirmationDialog("完全に削除しますか？", isPresented: Binding(get: { permanentDeletion != nil }, set: { if !$0 { permanentDeletion = nil } }), titleVisibility: .visible) {
            if let item = permanentDeletion {
                Button("完全に削除", role: .destructive) { taskOwner.startTask(.permanentlyDelete(item.id), on: model); permanentDeletion = nil }
                    .accessibilityIdentifier("library.confirmPermanentDelete")
            }
        } message: {
            if let item = permanentDeletion {
                Text("「\(item.displayTitle)」と、この項目の下書きを完全に削除します。元に戻せません。")
            }
        }
        .tint(.nibbleAccent)
        .detectAnimationLeaks()
        // Keep native presentation transactions outside app content; local scopes own its animation.
        .animationBarrier(warnsOnLeaks: false)
        .onAppear {
            if model.refreshOnAppearance { taskOwner.startTask(.refresh, on: model) }
        }
        .onChange(of: model.readDemand) {
            if model.readDemand != nil { taskOwner.startTask(.refresh, on: model) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active && model.refreshOnAppearance { taskOwner.startTask(.refresh, on: model) }
            else if scenePhase == .background { taskOwner.endScreen() }
        }
        .onDisappear {
            taskOwner.endScreen()
        }
    }

}
