import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreview: @MainActor EquatableBodyView {
    let document: MarkdownDocument

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if document.previewBlocks.isEmpty {
                Text("本文を入力すると、ここで見た目を確認できます。")
                    .font(.nibbleBody)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(document.previewBlocks) { block in
                    MarkdownPreviewBlock(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
    }
}
