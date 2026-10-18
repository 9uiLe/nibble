import AppMacros
import SwiftUI

@MainActor @Equatable
struct DeletedSnippetsView: View {
    private let inputRevision = UUID()
    @State private var model: LibraryModel
    @FocusState private var searching: Bool
    @Environment(\.scenePhase) private var phase
    @SkipEquatable let onReturn: () -> Void
    init(store: any LibraryStorage, effects: any LibraryEffects, onReturn: @escaping () -> Void) {
        _model = State(initialValue: LibraryModel(store: store, effects: effects, surface: .deleted))
        self.onReturn = onReturn
    }
    var body: some View {
        LibraryScreen(model: model, searchFocused: $searching, noticesPresented: phase == .active)
            .navigationTitle("削除した項目").navigationBarTitleDisplayMode(.inline)
            .onChange(of: phase, initial: true) { model.setNoticePresentation(phase == .active) }
            .onDisappear { model.setNoticePresentation(false); onReturn() }
            .sensoryFeedback(.success, trigger: model.feedback)
    }
}
