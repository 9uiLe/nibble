import AppMacros
import SwiftUI

@Equatable
struct LibrarySnippetRow: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let item: SnippetSummary
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    @Binding var permanentDeletion: SnippetSummary?

    var body: some View {
        SnippetRow(item: item, isTrash: model.contentRequest.filter == .trash,
                   unusedSince: model.contentRequest.filter != .trash && item.isDeletionCandidate(at: model.evaluatedAt) ? item.lastUsedAt : nil,
                   perform: { action in
            switch action {
            case .edit:
                searchFocused.wrappedValue = false
                taskOwner.startTask(.open(.snippet(item.id)), on: model)
            case .copy: taskOwner.startTask(.copy(item.id), on: model)
            case .pin: taskOwner.startTask(.pin(item), on: model)
            case .delete: taskOwner.startTask(.delete(item.id), on: model)
            case .restore: taskOwner.startTask(.restore(item.id), on: model)
            case .permanentlyDelete: permanentDeletion = item
            }
        })
    }
}
