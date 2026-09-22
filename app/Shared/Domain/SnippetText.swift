import Foundation
import Darwin

enum SnippetText {
    static let titleByteLimit = 512
    static let bodyByteLimit = 1_000_000
    static let previewLength = 180

    static func hasBody(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Compare the original bytes, including canonically equivalent Unicode.
    /// Contiguous buffers avoid UTF8View's per-byte iteration on long input.
    static func hasSameBytes(_ lhs: String, _ rhs: String) -> Bool {
        var lhs = lhs, rhs = rhs
        return lhs.withUTF8 { left in
            rhs.withUTF8 { right in
                guard left.count == right.count else { return false }
                guard !left.isEmpty else { return true }
                return memcmp(left.baseAddress!, right.baseAddress!, left.count) == 0
            }
        }
    }

    static func searchKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .replacingOccurrences(of: "\0", with: "\u{FFFD}")
    }

    static func validate(title: String, body: String) throws {
        guard hasBody(body) else { throw StoreError.empty }
        guard title.utf8.count <= titleByteLimit, body.utf8.count <= bodyByteLimit else { throw StoreError.tooLarge }
    }
}
