import AppMacros
import SwiftUI

@Equatable
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
            Text(model.emptyContent.message)
                .font(.nibbleBody)
        } actions: {
            if model.canShowAll {
                Button("すべてを見る") { model.showAll() }
                    .font(.nibbleTitle)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier("library.showAll")
            }
        }
        .padding(.vertical, 30)
        .listRowSeparator(.hidden)
    }
}
