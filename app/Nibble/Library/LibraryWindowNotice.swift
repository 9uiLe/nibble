import AppMacros
import SwiftUI

@Equatable
struct LibraryWindowNotice: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner

    var body: some View {
        LibraryNotice(model: model, restore: { taskOwner.startTask(.undoNotice($0), on: model) }, inWindow: true)
            .id(model.noticeContext.id)
            .tint(.nibbleAccent)
            .modifier(NibbleInterface())
            .privacySensitive()
    }
}
