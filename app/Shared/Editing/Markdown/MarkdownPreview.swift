import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreview: @MainActor EquatableBodyView {
    let document: MarkdownDocument

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.previewBlocks) { block in MarkdownPreviewBlock(block: block) }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityIdentifier("editor.preview")
    }
}
