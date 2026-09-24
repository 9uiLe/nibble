import Foundation

/// Variable markers live in the original body. Expansion produces a new value only
/// when the user explicitly uses the snippet; it never edits the saved text.
struct SnippetVariables: Sendable, Equatable {
    let body: String
    let names: [String]

    init(_ body: String) {
        self.body = body
        var found: [String] = []
        var seen: Set<String> = []
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            let name = String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if Self.valid(name), seen.insert(name).inserted { found.append(name) }
            cursor = end.upperBound
        }
        names = found
    }

    func filled(with values: [String: String]) -> String? {
        guard names.allSatisfy({ values[$0]?.isEmpty == false }) else { return nil }
        var result = ""
        var cursor = body.startIndex
        while let start = body.range(of: "{{", range: cursor..<body.endIndex),
              let end = body.range(of: "}}", range: start.upperBound..<body.endIndex) {
            result += body[cursor..<start.lowerBound]
            let name = String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
            if Self.valid(name), let value = values[name] { result += value }
            else { result += body[start.lowerBound..<end.upperBound] }
            cursor = end.upperBound
        }
        result += body[cursor...]
        return result
    }

    static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 40 && !name.contains("{") && !name.contains("}")
            && !name.contains("\n") && !name.contains("\r")
    }
}
