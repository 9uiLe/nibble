import AppMacros
import SwiftUI

@Equatable
struct DeletedSnippetsView: View {
    private let inputRevision = UUID()
    @State private var model: LibraryModel
    @State private var noticeTaskOwner = LibraryTaskOwner()
    @FocusState private var searchFocused: Bool
    let onReturn: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    init(store: any LibraryStorage & DraftEditing, effects: any LibraryEffects,
         onReturn: @escaping () -> Void) {
        _model = State(initialValue: LibraryModel(store: store, effects: effects, surface: .deleted))
        self.onReturn = onReturn
    }

    var body: some View {
        @Bindable var library = model
        LibraryScreen(model: model,
                      searchFocused: $searchFocused, advertisement: nil)
            .modifier(LibraryNoticeOverlay(model: model, taskOwner: noticeTaskOwner,
                                           isPresented: model.noticeContext.isPresented))
        .searchable(text: $library.query, prompt: "削除した項目を検索")
        .searchFocused($searchFocused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { searchFocused = false }
        .sensoryFeedback(.success, trigger: model.feedback)
        .onAppear { model.setNoticePresentation(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setNoticePresentation(scenePhase == .active) }
        .onDisappear {
            model.setNoticePresentation(false)
            noticeTaskOwner.endScreen()
            onReturn()
        }
    }
}
