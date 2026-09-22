import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreview: @MainActor EquatableBodyView {
    let highlighting: MarkdownHighlighting

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if highlighting.blocks.isEmpty {
                Text("本文を入力すると、ここで見た目を確認できます。")
                    .font(.nibbleBody)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(highlighting.blocks) { block in
                    MarkdownPreviewBlock(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.preview")
    }
}
