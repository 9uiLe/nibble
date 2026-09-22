import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct LibraryScreen: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @SkipEquatable let model: LibraryModel
    let surface: LibrarySurface
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    @Environment(\.scenePhase) private var scenePhase
    @State private var taskOwner = LibraryTaskOwner()
    @State private var permanentDeletion: SnippetSummary?

    var body: some View {
        @Bindable var library = model
        VStack(spacing: 0) {
            if surface.isRoot {
                RootScreenHeading(title: surface.title, subtitle: subtitle, model: model,
                               showsCreation: !searchFocused.wrappedValue)
            }
            if surface.showsSearchPrompt { LibrarySearchBar(model: model, searchFocused: searchFocused) }
            if surface.showsFilters {
                LibraryFilterBar(selection: $library.filter, counts: model.snapshot?.page.counts)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LibraryList(model: model, taskOwner: taskOwner, surface: surface, searchFocused: searchFocused,
                        permanentDeletion: $permanentDeletion)
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
            if !model.retainsFilters || model.snapshot == nil { taskOwner.startTask(.refresh, on: model) }
        }
        .onChange(of: model.request) { old, new in
            if !model.retainsFilters || old.query != new.query || old.filter == new.filter {
                taskOwner.startTask(.refresh, on: model)
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active && !model.retainsFilters { taskOwner.startTask(.refresh, on: model) }
            else if scenePhase == .background { taskOwner.endScreen() }
        }
        .onDisappear {
            taskOwner.endScreen()
        }
    }

    private var subtitle: String {
        if surface.showsFilters, let counts = model.snapshot?.page.counts {
            return "保存した項目 \(counts.saved)件"
        }
        return surface.showsFilters ? "保存した文章やURL" : "タイトルや本文の言葉で探す"
    }
}
