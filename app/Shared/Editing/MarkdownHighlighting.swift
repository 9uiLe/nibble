import Foundation

/// Ranges refer to the untouched source, including its Markdown punctuation.
struct MarkdownHighlighting: Equatable, Sendable {
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
            guard let position = run.markdownSourcePosition,
                  let range = input.range(for: position) else { continue }
            let inline = run.inlinePresentationIntent ?? []
            var heading: Int?
            var code = inline.contains(.code)
            var quote = false
            for component in run.presentationIntent?.components ?? [] {
                switch component.kind {
                case .header(level: let level): heading = level
                case .codeBlock: code = true
                case .blockQuote: quote = true
                default: break
                }
            }
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
