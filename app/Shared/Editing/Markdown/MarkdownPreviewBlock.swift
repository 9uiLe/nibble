import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreviewBlock: @MainActor EquatableBodyView {
    let block: MarkdownDocument.Block

    var equatableBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let marker = block.listMarker { Text(verbatim: marker).accessibilityHidden(true) }
            Text(block.text)
                .font(block.style.previewFont)
                .foregroundStyle(block.style.quote ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(block.style.heading == nil ? [] : .isHeader)
        }
        .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 16)
        .padding(.vertical, block.style.code ? 8 : 0)
        .padding(.horizontal, block.style.code ? 8 : 0)
        .background(block.style.code ? Color.secondary.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 6))
    }
}
