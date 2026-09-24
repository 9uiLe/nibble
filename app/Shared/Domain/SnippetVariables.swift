import Foundation

/// Variable markers live in the original body. Expansion produces a new value only
/// when the user explicitly uses the snippet; it never edits the saved text.
struct SnippetVariables: Sendable, Equatable {
    let body: String
    let names: [String]
    private let parts: [Part]

    private enum Part: Sendable, Equatable {
        case text(Substring)
        case variable(String)
    }

    init(_ body: String) {
        self.body = body
        var found: [String] = []
        var seen: Set<String> = []
        var parts: [Part] = []
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            parts.append(.text(body[cursor..<start.lowerBound]))
            let name = String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if Self.valid(name) {
                parts.append(.variable(name))
            } else {
                parts.append(.text(body[start.lowerBound..<end.upperBound]))
            }
            if Self.valid(name), seen.insert(name).inserted { found.append(name) }
            cursor = end.upperBound
        }
        parts.append(.text(body[cursor...]))
        names = found
        self.parts = parts
    }

    func filled(with values: [String: String]) -> String? {
        guard names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        result.reserveCapacity(body.utf8.count)
        for part in parts {
            switch part {
            case .text(let text): result += text
            case .variable(let name): result += values[name] ?? ""
            }
        }
        return result
    }

    /// Expands only the characters needed by a collapsed preview. `hasMore` is
    /// determined by observing one further character, without building the body.
    func filledPrefix(with values: [String: String], characterLimit: Int) -> (text: String, hasMore: Bool)? {
        guard characterLimit >= 0, names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        result.reserveCapacity(characterLimit)
        for part in parts {
            let text: Substring
            switch part {
            case .text(let value): text = value
            case .variable(let name): text = values[name, default: ""][...]
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

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 40 && !name.contains("{") && !name.contains("}")
            && !name.contains("\n") && !name.contains("\r")
    }

    static func marker(for name: String) -> String? {
        valid(name) ? "{{\(name)}}" : nil
    }
}
