import AppMacros
import SwiftUI

@Equatable
struct CreateSnippetButton: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @State private var taskOwner = LibraryTaskOwner()

    var body: some View {
        Button {
            taskOwner.startTask(.open(.new), on: model)
        } label: {
            Image(systemName: "plus")
                .resizable()
                .scaledToFit()
                .frame(width: InterfaceMetrics.creationSymbolSize, height: InterfaceMetrics.creationSymbolSize)
                .frame(width: InterfaceMetrics.creationSize, height: InterfaceMetrics.creationSize)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("新規作成")
        .accessibilityHint("編集画面を開きます")
        .accessibilityIdentifier("library.add")
        .keyboardShortcut("n", modifiers: .command)
        .onDisappear { taskOwner.endScreen() }
    }
}
