import AppMacros
import SwiftUI

@Equatable
struct MarkdownPreviewBlock: @MainActor EquatableBodyView {
    let block: MarkdownHighlighting.Block

    var equatableBody: some View {
        HStack(alignment: .top, spacing: 8) {
            if let marker = block.listMarker {
                Text(marker).font(.nibbleBody)
            }
            Text(Self.styledText(block))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(block.quote ? .secondary : .primary)
        .padding(block.code ? 12 : 0)
        .background(block.code ? Color.nibbleSoft : .clear, in: .rect(cornerRadius: 8))
        .padding(.leading, block.quote ? 12 : 0)
        .overlay(alignment: .leading) {
            if block.quote {
                Rectangle().fill(.tertiary).frame(width: 2)
            }
        }
        .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 16)
        .accessibilityAddTraits(block.heading != nil ? .isHeader : [])
    }

    static func styledText(_ block: MarkdownHighlighting.Block) -> AttributedString {
        var text = block.text
        for run in block.text.runs {
            let inline = run.inlinePresentationIntent ?? []
            let code = block.code || inline.contains(.code)
            let size: CGFloat = block.heading.map { [26.0, 22, 19, 17, 15, 13][min(5, max(0, $0 - 1))] } ?? 13
            var font = Font.system(size: size, weight: block.heading != nil || inline.contains(.stronglyEmphasized) ? .bold : .regular,
                                   design: code ? .monospaced : .default)
            if inline.contains(.emphasized) { font = font.italic() }
            text[run.range].font = font
            if inline.contains(.code), !block.code { text[run.range].backgroundColor = .nibbleSoft }
            if inline.contains(.strikethrough) { text[run.range].strikethroughStyle = .single }
        }
        return text
    }
}
