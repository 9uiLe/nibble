import Foundation

struct MarkdownDocument: Equatable, Sendable {
    struct Span: Equatable, Sendable {
        let range: NSRange
        let style: MarkdownStyle
    }
    struct Block: Equatable, Identifiable, Sendable {
        let id: Int
        var text: AttributedString
        let style: MarkdownStyle
        let listMarker: String?
        let listDepth: Int
    }

    private(set) var source = ""
    private(set) var sourceSpans: [Span] = []
    private(set) var previewBlocks: [Block] = []

    @concurrent
    static func parse(_ source: String) async -> Self {
        var document = Self(source: source)
        guard !Task.isCancelled else { return document }
        let positions = Positions(source)
        guard !Task.isCancelled else { return document }
        let options = AttributedString.MarkdownParsingOptions(appliesSourcePositionAttributes: true)
        guard let parsed = try? AttributedString(markdown: positions.markdown, options: options) else {
            document.previewBlocks = [.init(id: 0, text: AttributedString(source),
                                            style: MarkdownStyle(), listMarker: nil, listDepth: 0)]
            return document
        }
        for run in parsed.runs {
            guard !Task.isCancelled else { return Self(source: source) }
            var blockStyle = MarkdownStyle()
            var ordinal: Int?
            var ordered: Bool?
            var depth = 0
            let components = run.presentationIntent?.components ?? []
            for component in components {
                switch component.kind {
                case .header(let level): blockStyle.heading = level
                case .blockQuote: blockStyle.quote = true
                case .codeBlock: blockStyle.code = true
                case .listItem(let number): if ordinal == nil { ordinal = number }
                case .orderedList:
                    ordered = ordered ?? true
                    depth += 1
                case .unorderedList:
                    ordered = ordered ?? false
                    depth += 1
                default: break
                }
            }
            let identifier = components.first?.identity ?? 0
            let text = AttributedString(parsed[run.range])
            if document.previewBlocks.last?.id == identifier {
                document.previewBlocks[document.previewBlocks.count - 1].text.append(text)
            } else {
                document.previewBlocks.append(.init(id: identifier, text: text, style: blockStyle,
                    listMarker: ordinal.map { ordered == true ? "\($0)." : "•" }, listDepth: depth))
            }
            guard let location = run.markdownSourcePosition,
                  let range = positions.range(location) else { continue }
            let style = blockStyle.applying(run.inlinePresentationIntent ?? [], link: run.link != nil)
            document.sourceSpans.append(.init(range: range, style: style))
        }
        return document
    }

    // Only byte/UTF-16 differences need checkpoints; ASCII does not need a per-byte table.
    private struct Positions {
        let markdown: String
        private var lineStarts = [0]
        private var differences: [(end: Int, delta: Int)] = [(0, 0)]
        private var byteCount = 0

        init(_ source: String) {
            markdown = source.replacingOccurrences(of: "\0", with: "\u{FFFD}")
            var units = 0
            var previousCR = false
            for scalar in source.unicodeScalars {
                let bytes = scalar.value == 0 ? 3 : scalar.utf8.count
                byteCount += bytes
                units += scalar.utf16.count
                if bytes != scalar.utf16.count {
                    differences.append((byteCount, byteCount - units))
                }
                switch scalar.value {
                case 13: lineStarts.append(byteCount)
                case 10:
                    if previousCR { lineStarts[lineStarts.count - 1] = byteCount }
                    if !previousCR { lineStarts.append(byteCount) }
                default: break
                }
                previousCR = scalar.value == 13
            }
        }

        func range(_ position: AttributedString.MarkdownSourcePosition) -> NSRange? {
            guard position.startLine > 0, position.startLine <= lineStarts.count,
                  position.endLine >= position.startLine, position.endLine <= lineStarts.count,
                  position.startColumn > 0 else { return nil }
            let lower = lineStarts[position.startLine - 1] + position.startColumn - 1
            let upper = lineStarts[position.endLine - 1] + position.endColumn
            guard lower >= 0, lower <= upper, upper <= byteCount else { return nil }
            let start = utf16(lower)
            return NSRange(location: start, length: utf16(upper) - start)
        }

        private func utf16(_ byte: Int) -> Int {
            var lower = 0
            var upper = differences.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if differences[middle].end <= byte { lower = middle + 1 }
                if differences[middle].end > byte { upper = middle }
            }
            return byte - differences[max(0, lower - 1)].delta
        }
    }
}
