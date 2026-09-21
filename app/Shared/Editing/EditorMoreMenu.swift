import AppMacros
import SwiftUI

@Equatable
struct EditorMoreMenu: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @Binding var confirmsDiscard: Bool

    var body: some View {
        Menu {
            ShareLink(item: model.body) { Label("本文を共有", systemImage: "square.and.arrow.up") }
                .disabled(model.body.isEmpty)
            Button("下書きを破棄", systemImage: "trash", role: .destructive) { confirmsDiscard = true }
                .accessibilityIdentifier("editor.discard")
        } label: {
            Label("その他", systemImage: "ellipsis")
                .modifier(IconControlStyle())
        }
        .buttonStyle(.plain)
        // The touch region includes the padding around the visible icon.
        .frame(width: InterfaceMetrics.touchSize, height: InterfaceMetrics.touchSize)
        .contentShape(.rect)
        .accessibilityLabel("その他")
        .accessibilityIdentifier("editor.more")
    }
}
