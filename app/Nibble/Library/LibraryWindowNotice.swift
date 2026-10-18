import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryWindowNotice: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    var body: some View {
        LibraryNotice(model: model, taskOwner: taskOwner)
            .id(model.noticeContext.id).modifier(NibbleInterface()).privacySensitive()
    }
}
