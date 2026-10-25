import Foundation

/// Only valid {{name}} tokens are substituted. All other bytes remain literal.
struct TextTemplate: Equatable, Sendable {
    private enum Segment: Equatable, Sendable {
        case literal([UInt8])
        case variable(String)
    }

    let body: String
    let names: [String]
    private let segments: [Segment]

    init(_ body: String) {
        self.body = body
        let bytes = Array(body.utf8)
        var parsed: [Segment] = []
        var found: [String] = []
        var literalStart = 0
        var cursor = 0
        while cursor + 1 < bytes.count {
            guard bytes[cursor] == 123, bytes[cursor + 1] == 123 else {
                cursor += 1
                continue
            }
            let opening = cursor
            var closing = cursor + 2
            while closing + 1 < bytes.count, !(bytes[closing] == 125 && bytes[closing + 1] == 125) {
                closing += 1
            }
            guard closing + 1 < bytes.count else { break }
            let raw = String(decoding: bytes[(opening + 2)..<closing], as: UTF8.self)
            let name = raw.trimmingCharacters(in: .whitespaces)
            let valid = !name.isEmpty && !name.contains(where: { $0.isNewline || $0 == "{" || $0 == "}" })
            guard valid else {
                cursor = closing + 2
                continue
            }
            if literalStart < opening { parsed.append(.literal(Array(bytes[literalStart..<opening]))) }
            parsed.append(.variable(name))
            if !found.contains(name) { found.append(name) }
            cursor = closing + 2
            literalStart = cursor
        }
        if literalStart < bytes.count { parsed.append(.literal(Array(bytes[literalStart...]))) }
        names = found
        segments = parsed
    }

    func render(values: [String: String]) throws -> String {
        let missing = names.filter { name in
            guard let value = values[name] else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard missing.isEmpty else { throw WorkspaceError.missingValues(missing) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(body.utf8.count)
        for segment in segments {
            switch segment {
            case .literal(let literal): bytes.append(contentsOf: literal)
            case .variable(let name):
                guard let value = values[name] else { throw WorkspaceError.missingValues([name]) }
                bytes.append(contentsOf: value.utf8)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
