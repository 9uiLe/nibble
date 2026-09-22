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
        guard !Task.isCancelled,
              let parsed = try? AttributedString(markdown: source, options: .init(appliesSourcePositionAttributes: true)) else {
            return Self(source: source)
        }
        // Source columns are UTF-8 bytes. Map them once, including multi-byte scalars,
        // rather than repeatedly traversing a long String for every style run.
        var lineStarts = [0]
        var utf16Offsets = [Int]()
        utf16Offsets.reserveCapacity(source.utf8.count + 1)
        var utf16 = 0
        for scalar in source.unicodeScalars {
            for _ in scalar.utf8 { utf16Offsets.append(utf16) }
            utf16 += scalar.utf16.count
            if scalar == "\n" { lineStarts.append(utf16Offsets.count) }
        }
        utf16Offsets.append(utf16)
        var result = Self(source: source)
        for run in parsed.runs {
            if Task.isCancelled { return Self(source: source) }
            guard let position = run.markdownSourcePosition,
                  position.startLine > 0, position.endLine <= lineStarts.count else { continue }
            let start = lineStarts[position.startLine - 1] + position.startColumn - 1
            let end = lineStarts[position.endLine - 1] + position.endColumn
            guard start >= 0, end >= start, end < utf16Offsets.count else { continue }
            let range = NSRange(location: utf16Offsets[start], length: utf16Offsets[end] - utf16Offsets[start])
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
}
