import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreviewBlock: @MainActor EquatableBodyView {
    let block: MarkdownDocument.Block

    var equatableBody: some View {
        HStack(alignment: .top, spacing: 8) {
            if let marker = block.listMarker {
                Text(marker).font(.nibbleBody)
            }
            Text(Self.styledText(block))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("editor.preview.block.\(block.id)")
                .accessibilityAddTraits(block.style.heading != nil ? .isHeader : [])
        }
        .foregroundStyle(block.style.quote ? .secondary : .primary)
        .padding(block.style.code ? 12 : 0)
        .background(block.style.code ? Color.nibbleSoft : .clear, in: .rect(cornerRadius: 8))
        .padding(.leading, block.style.quote ? 12 : 0)
        .overlay(alignment: .leading) {
            if block.style.quote {
                Rectangle().fill(.tertiary).frame(width: 2)
            }
        }
        .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 16)
    }

    static func styledText(_ block: MarkdownDocument.Block) -> AttributedString {
        var text = block.text
        for run in block.text.runs {
            let style = block.style.applying(run.inlinePresentationIntent ?? [], link: run.link != nil)
            text[run.range].font = style.previewFont
            if style.code, !block.style.code { text[run.range].backgroundColor = .nibbleSoft }
            if style.strike { text[run.range].strikethroughStyle = .single }
        }
        return text
    }
}
