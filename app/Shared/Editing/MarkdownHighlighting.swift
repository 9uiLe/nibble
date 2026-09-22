import Foundation

/// Ranges refer to the untouched source, including its Markdown punctuation.
struct MarkdownHighlighting: Equatable, Sendable {
    struct Block: Equatable, Identifiable, Sendable {
        let id: Int
        var text: AttributedString
        let heading: Int?
        let code: Bool
        let quote: Bool
        let listMarker: String?
        let listDepth: Int
    }

    struct Span: Equatable, Sendable {
        let range: NSRange
        let heading: Int?
        let bold: Bool
        let italic: Bool
        let code: Bool
        let strike: Bool
        let quote: Bool
        let link: Bool
    }
    var source = ""
    var spans: [Span] = []
    var blocks: [Block] = []

    @concurrent
    static func parse(_ source: String) async -> Self {
        guard !Task.isCancelled else { return Self(source: source) }
        let input = SourceMap(source)
        guard !Task.isCancelled,
              let parsed = try? AttributedString(markdown: input.markdown, options: .init(appliesSourcePositionAttributes: true)) else {
            return Self(source: source)
        }
        var result = Self(source: source)
        for run in parsed.runs {
            if Task.isCancelled { return Self(source: source) }
            let inline = run.inlinePresentationIntent ?? []
            var heading: Int?
            var code = inline.contains(.code)
            var codeBlock = false
            var quote = false
            var listItem: Int?
            var orderedList: Bool?
            var listDepth = 0
            for component in run.presentationIntent?.components ?? [] {
                switch component.kind {
                case .header(level: let level): heading = level
                case .codeBlock: code = true; codeBlock = true
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
            if result.blocks.last?.id == blockID {
                result.blocks[result.blocks.count - 1].text.append(content)
            } else {
                let marker = listItem.map { orderedList == true ? "\($0)." : "•" }
                result.blocks.append(Block(id: blockID, text: content, heading: heading, code: codeBlock,
                                           quote: quote, listMarker: marker, listDepth: listDepth))
            }
            guard let position = run.markdownSourcePosition,
                  let range = input.range(for: position) else { continue }
            result.spans.append(Span(range: range, heading: heading,
                                     bold: inline.contains(.stronglyEmphasized),
                                     italic: inline.contains(.emphasized), code: code,
                                     strike: inline.contains(.strikethrough), quote: quote, link: run.link != nil))
        }
        return result
    }

    /// Maps parser byte columns to UTF-16 ranges in the untouched editor source.
    private struct SourceMap {
        let markdown: String
        private var lineStarts = [0]
        private var utf16Offsets = [Int]()

        init(_ source: String) {
            // Markdown parses NUL as U+FFFD. Its three bytes still refer to one
            // original code unit; this copy is never written back to the editor.
            markdown = source.replacingOccurrences(of: "\0", with: "\u{FFFD}")
            utf16Offsets.reserveCapacity(markdown.utf8.count + 1)
            var utf16 = 0
            var previousWasCR = false
            for scalar in source.unicodeScalars {
                let byteCount = scalar == "\0" ? 3 : scalar.utf8.count
                utf16Offsets.append(contentsOf: repeatElement(utf16, count: byteCount))
                utf16 += scalar.utf16.count
                if scalar == "\r" {
                    lineStarts.append(utf16Offsets.count)
                } else if scalar == "\n" {
                    if previousWasCR { lineStarts[lineStarts.count - 1] = utf16Offsets.count }
                    else { lineStarts.append(utf16Offsets.count) }
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
