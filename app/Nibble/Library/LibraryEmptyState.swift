import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryEmptyState: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    var body: some View {
        ContentUnavailableView {
            Label {
                Text(model.emptyContent.title).font(.nibbleTitle)
            } icon: {
                Image(systemName: model.emptyContent.symbol)
            }
        } description: {
            Text(model.emptyContent.message).font(.nibbleBody)
        } actions: {
            if model.canShowAll { Button("すべてを見る") { model.showAll() }.font(.nibbleTitle).frame(minHeight: 44) }
        }.accessibilityIdentifier("library.empty")
    }
}
