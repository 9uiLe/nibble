import AppMacros
import SwiftUI

@Equatable
struct LibraryEmptyState: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(model.emptyContent.title).font(.nibbleTitle).foregroundStyle(Color.nibblePrimary)
            } icon: {
                Image(systemName: model.emptyContent.symbol)
            }
        } description: {
            Text(model.emptyContent.message)
                .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
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
