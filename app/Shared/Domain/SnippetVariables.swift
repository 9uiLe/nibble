import Foundation

struct VariableName: Hashable, Sendable {
    enum Issue: Equatable, Sendable {
        case empty
        case tooLong
        case unsupportedCharacter
    }

    let text: String
    var marker: String { "{{" + text + "}}" }

    init?(_ source: String) {
        guard Self.issue(source) == nil else { return nil }
        text = source.trimmingCharacters(in: .whitespaces)
    }

    static func issue(_ source: String) -> Issue? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= 40 else { return .tooLong }
        let forbidden = CharacterSet(charactersIn: "{}\r\n")
        return trimmed.unicodeScalars.contains(where: forbidden.contains) ? .unsupportedCharacter : nil
    }
}

/// Tokens reference source ranges, so only a confirmed expansion allocates the
/// complete output. Invalid or unfinished markers remain literal source text.
struct SnippetVariables: Equatable, Sendable {
    private enum Token: Equatable, Sendable {
        case literal(Range<String.Index>)
        case value(VariableName)
    }

    let body: String
    let names: [VariableName]
    private let tokens: [Token]

    init(_ source: String) {
        body = source
        var unique: [VariableName] = []
        var parsed: [Token] = []
        var next = source.startIndex
        while next < source.endIndex {
            guard let opening = source.range(of: "{{", range: next..<source.endIndex),
                  let closing = source.range(of: "}}", range: opening.upperBound..<source.endIndex) else {
                parsed.append(.literal(next..<source.endIndex))
                break
            }
            parsed.append(.literal(next..<opening.lowerBound))
            if let name = VariableName(String(source[opening.upperBound..<closing.lowerBound])) {
                parsed.append(.value(name))
                if !unique.contains(name) { unique.append(name) }
            } else {
                parsed.append(.literal(opening.lowerBound..<closing.upperBound))
            }
            next = closing.upperBound
        }
        names = unique
        tokens = parsed
    }

    private func prepared(_ values: [VariableName: String]) -> Bool {
        names.allSatisfy { name in
            guard let text = values[name] else { return false }
            return !text.isEmpty
        }
    }

    private func text(for token: Token, values: [VariableName: String]) -> Substring {
        switch token {
        case .literal(let range): body[range]
        case .value(let name): values[name, default: ""][...]
        }
    }

    func filled(with values: [VariableName: String]) -> String? {
        guard prepared(values) else { return nil }
        return tokens.reduce(into: "") { result, token in
            result.append(contentsOf: text(for: token, values: values))
        }
    }

    func filledPrefix(with values: [VariableName: String], characterLimit: Int) -> (text: String, hasMore: Bool)? {
        guard characterLimit >= 0, prepared(values) else { return nil }
        let budget = min(characterLimit, Int.max - 2)
        var output = ""
        for token in tokens {
            var remaining = text(for: token, values: values)
            while !remaining.isEmpty {
                let available = max(1, budget - min(output.count, budget) + 2)
                let slice = remaining.prefix(available)
                output.append(contentsOf: slice)
                remaining = remaining[slice.endIndex...]
                // Keep one additional whole grapheme because the next segment
                // can extend the final one (combining marks, ZWJ or CR + LF).
                if output.count > characterLimit && output.count - characterLimit > 1 {
                    return (String(output.prefix(characterLimit)), true)
                }
            }
        }
        return (String(output.prefix(characterLimit)), output.count > characterLimit)
    }
}
