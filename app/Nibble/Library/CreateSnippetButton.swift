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
                .font(.system(size: 24, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
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
