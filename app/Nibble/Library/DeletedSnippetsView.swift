import AppMacros
import SwiftUI

@Equatable
struct DeletedSnippetsView: View {
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
                        Button { dismiss() } label: {
                            Label("閉じる", systemImage: "xmark")
                                .modifier(IconControlStyle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library.trash.close")
                    }
                    .sharedBackgroundVisibility(.hidden)
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
