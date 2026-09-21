import AppMacros
import SwiftUI

@Equatable
struct EditorKeyboardAccessory: View {
    private let inputRevision = UUID()
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    let showHelp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { showHelp() } label: {
                Label("入力の上限と保存について", systemImage: "info")
                    .modifier(IconControlStyle())
            }
            .accessibilityIdentifier("editor.keyboard.help")
            Spacer(minLength: 12)
            Button { focus.wrappedValue = nil } label: {
                Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
                    .modifier(IconControlStyle())
            }
            .accessibilityLabel("キーボードを閉じる")
            .accessibilityIdentifier("editor.keyboard.dismiss")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.keyboard.accessory")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
