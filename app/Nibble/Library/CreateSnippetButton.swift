import AppMacros
import SwiftUI

@Equatable
struct CreateSnippetButton: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    var prominent = false
    @State private var taskOwner = LibraryTaskOwner()

    var body: some View {
        Button {
            taskOwner.startTask(.open(.new), on: model)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                if prominent { Text("新規作成").font(.system(size: 15, weight: .semibold)) }
            }
            .frame(maxWidth: prominent ? .infinity : nil)
            .frame(minWidth: 44, minHeight: prominent ? 48 : 44)
            .foregroundStyle(prominent ? Color.nibbleCanvas : Color.primary)
            .background(prominent ? Color.nibbleAccent : Color.clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新規作成")
        .accessibilityHint("編集画面を開きます")
        .accessibilityIdentifier("library.add")
        .keyboardShortcut("n", modifiers: .command)
        .onDisappear { taskOwner.endScreen() }
    }
}
