import Darwin
import Foundation

enum SnippetText {
    static let previewLength = 180
    static let bodyByteLimit = 1_000_000
    static let titleByteLimit = 512

    static func hasBody(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func validate(title: String, body: String) throws {
        guard hasBody(body) else { throw StoreError.empty }
        if body.utf8.count > bodyByteLimit || title.utf8.count > titleByteLimit {
            throw StoreError.tooLarge
        }
    }

    static func hasSameBytes(_ first: String, _ second: String) -> Bool {
        var first = first
        var second = second
        return first.withUTF8 { firstBytes in
            second.withUTF8 { secondBytes in
                guard firstBytes.count == secondBytes.count else { return false }
                guard let firstAddress = firstBytes.baseAddress, let secondAddress = secondBytes.baseAddress else {
                    return firstBytes.isEmpty
                }
                return memcmp(firstAddress, secondAddress, firstBytes.count) == 0
            }
        }
    }

    static func searchKey(_ source: String) -> String {
        let canonical = source.precomposedStringWithCanonicalMapping
        let folded = canonical.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
        return folded.replacingOccurrences(of: "\0", with: "\u{FFFD}")
    }
}
