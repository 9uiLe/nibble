import Foundation

/// Variable markers live in the original body. Expansion produces a new value only
/// when the user explicitly uses the snippet; it never edits the saved text.
struct SnippetVariables: Sendable, Equatable {
    let body: String
    let names: [VariableName]
    private let parts: [Part]

    private enum Part: Sendable, Equatable {
        case text(Substring)
        case variable(VariableName)
    }

    init(_ body: String) {
        self.body = body
        var found: [VariableName] = []
        var seen: Set<VariableName> = []
        var parts: [Part] = []
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            parts.append(.text(body[cursor..<start.lowerBound]))
            let name = VariableName(String(body[start.upperBound..<end.lowerBound]))
            if let name {
                parts.append(.variable(name))
            } else {
                parts.append(.text(body[start.lowerBound..<end.upperBound]))
            }
            if let name, seen.insert(name).inserted { found.append(name) }
            cursor = end.upperBound
        }
        parts.append(.text(body[cursor...]))
        names = found
        self.parts = parts
    }

    func filled(with values: [VariableName: String]) -> String? {
        guard names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        result.reserveCapacity(body.utf8.count)
        for part in parts {
            switch part {
            case .text(let text): result += text
            case .variable(let name):
                guard let value = values[name] else { return nil }
                result += value
            }
        }
        return result
    }

    /// Expands only the characters needed by a collapsed preview. `hasMore` is
    /// determined by observing one further character, without building the body.
    func filledPrefix(with values: [VariableName: String], characterLimit: Int) -> (text: String, hasMore: Bool)? {
        guard characterLimit >= 0, names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        result.reserveCapacity(characterLimit)
        for part in parts {
            let text: Substring
            switch part {
            case .text(let value): text = value
            case .variable(let name):
                guard let value = values[name] else { return nil }
                text = value[...]
            }
            var remaining = text
            while !remaining.isEmpty {
                // A grapheme can span a marker boundary (for example, a base
                // character followed by a combining mark). Count the joined
                // string before deciding where the completed text is cut.
                let next = remaining.prefix(max(1, characterLimit + 1 - result.count))
                result.append(contentsOf: next)
                remaining = remaining[next.endIndex...]
                if result.count > characterLimit && !remaining.isEmpty {
                    return (String(result.prefix(characterLimit)), true)
                }
            }
        }
        let hasMore = result.count > characterLimit
        return (hasMore ? String(result.prefix(characterLimit)) : result, hasMore)
    }
}

/// A canonical marker name. Every instance has passed the marker grammar.
struct VariableName: Hashable, Sendable {
    enum Issue: Equatable, Sendable {
        case empty, tooLong, unsupportedCharacter
    }

    let text: String
    var marker: String { "{{\(text)}}" }

    init?(_ input: String) {
        guard Self.issue(input) == nil else { return nil }
        text = Self.canonical(input)
    }

    static func issue(_ input: String) -> Issue? {
        let name = canonical(input)
        if name.isEmpty { return .empty }
        if name.count > 40 { return .tooLong }
        if name.contains("{") || name.contains("}") || name.contains("\n") || name.contains("\r") {
            return .unsupportedCharacter
        }
        return nil
    }

    private static func canonical(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespaces)
    }
}
