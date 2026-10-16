import AppMacros
import SwiftUI

@Equatable
struct CreateSnippetButton: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    var prominent = false
    @State private var taskOwner = LibraryTaskOwner()

    var body: some View {
        Group {
            if prominent {
                Button {
                    taskOwner.startTask(.open(.new), on: model)
                } label: {
                    Label("新規作成", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IOSButtonStyle(.primary))
                .accessibilityLabel("新規作成")
                .accessibilityHint("編集画面を開きます")
                .accessibilityIdentifier("library.add")
                .keyboardShortcut("n", modifiers: .command)
            } else {
                Button {
                    taskOwner.startTask(.open(.new), on: model)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新規作成")
                .accessibilityHint("編集画面を開きます")
                .accessibilityIdentifier("library.add")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onDisappear { taskOwner.endScreen() }
    }
}
