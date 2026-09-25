import Foundation

/// One source snapshot produces UTF-16 decoration spans and syntax-free preview blocks.
struct MarkdownDocument: Equatable, Sendable {
    struct Block: Equatable, Identifiable, Sendable {
        let id: Int
        var text: AttributedString
        let style: MarkdownStyle
        let listMarker: String?
        let listDepth: Int
    }

    struct Span: Equatable, Sendable {
        let range: NSRange
        let style: MarkdownStyle
    }
    private(set) var source = ""
    private(set) var sourceSpans: [Span] = []
    private(set) var previewBlocks: [Block] = []

    @concurrent
    static func parse(_ source: String) async -> Self {
        guard !Task.isCancelled else { return Self(source: source) }
        let input = SourceMap(source)
        guard !Task.isCancelled else { return Self(source: source) }
        guard let parsed = try? AttributedString(markdown: input.markdown, options: .init(appliesSourcePositionAttributes: true)) else {
            return Self(source: source, previewBlocks: [Block(id: 0, text: AttributedString(source), style: MarkdownStyle(),
                                                              listMarker: nil, listDepth: 0)])
        }
        var result = Self(source: source)
        for run in parsed.runs {
            if Task.isCancelled { return Self(source: source) }
            let inline = run.inlinePresentationIntent ?? []
            var heading: Int?
            var codeBlock = false
            var quote = false
            var listItem: Int?
            var orderedList: Bool?
            var listDepth = 0
            for component in run.presentationIntent?.components ?? [] {
                switch component.kind {
                case .header(level: let level): heading = level
                case .codeBlock: codeBlock = true
                case .blockQuote: quote = true
                case .listItem(ordinal: let ordinal): if listItem == nil { listItem = ordinal }
                case .orderedList:
                    if orderedList == nil { orderedList = true }
                    listDepth += 1
                case .unorderedList:
                    if orderedList == nil { orderedList = false }
                    listDepth += 1
                default: break
                }
            }
            let blockID = run.presentationIntent?.components.first?.identity ?? 0
            let content = AttributedString(parsed[run.range])
            let style = MarkdownStyle(heading: heading, code: codeBlock, quote: quote)
            if result.previewBlocks.last?.id == blockID {
                result.previewBlocks[result.previewBlocks.count - 1].text.append(content)
            } else {
                let marker = listItem.map { orderedList == true ? "\($0)." : "•" }
                result.previewBlocks.append(Block(id: blockID, text: content, style: style,
                                                  listMarker: marker, listDepth: listDepth))
            }
            guard let position = run.markdownSourcePosition,
                  let range = input.range(for: position) else { continue }
            result.sourceSpans.append(Span(range: range, style: style.applying(inline, link: run.link != nil)))
        }
        return result
    }

    /// Maps parser byte columns to UTF-16 ranges in the untouched editor source.
    private struct SourceMap {
        let markdown: String
        private var lineStarts = [0]
        private var utf16Offsets = [Int]()

        init(_ source: String) {
            // Markdown parses NUL as U+FFFD. Its three bytes refer to one
            // original code unit; this copy is never written back to the editor.
            markdown = source.replacingOccurrences(of: "\0", with: "\u{FFFD}")
            utf16Offsets.reserveCapacity(markdown.utf8.count + 1)
            var utf16 = 0
            var previousWasCR = false
            for scalar in source.unicodeScalars {
                let byteCount = scalar == "\0" ? 3 : scalar.utf8.count
                utf16Offsets.append(contentsOf: repeatElement(utf16, count: byteCount))
                utf16 += scalar.utf16.count
                switch scalar {
                case "\r":
                    lineStarts.append(utf16Offsets.count)
                case "\n":
                    if previousWasCR { lineStarts[lineStarts.count - 1] = utf16Offsets.count }
                    else { lineStarts.append(utf16Offsets.count) }
                default:
                    break
                }
                previousWasCR = scalar == "\r"
            }
            utf16Offsets.append(utf16)
        }

        func range(for position: AttributedString.MarkdownSourcePosition) -> NSRange? {
            guard position.startLine > 0, position.endLine >= position.startLine,
                  position.endLine <= lineStarts.count, position.startColumn > 0 else { return nil }
            let start = lineStarts[position.startLine - 1] + position.startColumn - 1
            let end = lineStarts[position.endLine - 1] + position.endColumn
            guard end >= start, end < utf16Offsets.count else { return nil }
            return NSRange(location: utf16Offsets[start], length: utf16Offsets[end] - utf16Offsets[start])
        }
    }
}
