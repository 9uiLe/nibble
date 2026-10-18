import Foundation

/// Edits a local value without a responder, host document, or conversion engine.
struct KeyboardValueBuffer: Equatable, Sendable {
    private var bytes: Data
    private var anchor: Int
    private var cursor: Int
    private var readingBytes: Data?

    var text: String { String(decoding: bytes, as: UTF8.self) }
    var reading: String? { readingBytes.map { String(decoding: $0, as: UTF8.self) } }
    var selection: NSRange {
        NSRange(location: min(anchor, cursor), length: abs(cursor - anchor))
    }

    init(text: String = "") {
        bytes = Data(text.utf8)
        anchor = text.utf16.count
        cursor = anchor
    }

    init?(text: String, selection: NSRange) {
        guard Self.characterRange(selection, in: text) != nil else { return nil }
        bytes = Data(text.utf8)
        anchor = selection.location
        cursor = selection.location + selection.length
    }

    @discardableResult
    mutating func select(_ range: NSRange) -> Bool {
        guard readingBytes == nil, Self.characterRange(range, in: text) != nil else { return false }
        anchor = range.location
        cursor = range.location + range.length
        return true
    }

    @discardableResult
    mutating func replaceSelection(with replacement: String) -> Bool {
        guard readingBytes == nil else { return false }
        return replace(selection, with: replacement)
    }

    @discardableResult
    mutating func moveLeft(extendingSelection: Bool = false) -> Bool {
        guard readingBytes == nil else { return false }
        if !extendingSelection, anchor != cursor {
            return move(to: min(anchor, cursor), extendingSelection: false)
        }
        let previous = Self.boundaries(in: text).last { $0 < cursor } ?? 0
        return move(to: previous, extendingSelection: extendingSelection)
    }

    @discardableResult
    mutating func moveRight(extendingSelection: Bool = false) -> Bool {
        guard readingBytes == nil else { return false }
        if !extendingSelection, anchor != cursor {
            return move(to: max(anchor, cursor), extendingSelection: false)
        }
        let next = Self.boundaries(in: text).first { $0 > cursor } ?? text.utf16.count
        return move(to: next, extendingSelection: extendingSelection)
    }

    @discardableResult
    mutating func moveToStart(extendingSelection: Bool = false) -> Bool {
        guard readingBytes == nil else { return false }
        return move(to: 0, extendingSelection: extendingSelection)
    }

    @discardableResult
    mutating func moveToEnd(extendingSelection: Bool = false) -> Bool {
        guard readingBytes == nil else { return false }
        return move(to: text.utf16.count, extendingSelection: extendingSelection)
    }

    @discardableResult
    mutating func selectAll() -> Bool {
        guard readingBytes == nil else { return false }
        anchor = 0
        cursor = text.utf16.count
        return true
    }

    @discardableResult
    mutating func deleteBackward() -> Bool {
        guard readingBytes == nil else { return false }
        if selection.length > 0 { return replace(selection, with: "") }
        let previous = Self.boundaries(in: text).last { $0 < cursor } ?? cursor
        return replace(NSRange(location: previous, length: cursor - previous), with: "")
    }

    @discardableResult
    mutating func deleteForward() -> Bool {
        guard readingBytes == nil else { return false }
        if selection.length > 0 { return replace(selection, with: "") }
        let next = Self.boundaries(in: text).first { $0 > cursor } ?? cursor
        return replace(NSRange(location: cursor, length: next - cursor), with: "")
    }

    @discardableResult
    mutating func beginReading(_ initial: String = "") -> Bool {
        guard readingBytes == nil else { return false }
        readingBytes = Data(initial.utf8)
        return true
    }

    @discardableResult
    mutating func setReading(_ replacement: String) -> Bool {
        guard readingBytes != nil else { return false }
        readingBytes = Data(replacement.utf8)
        return true
    }

    @discardableResult
    mutating func appendReading(_ addition: String) -> Bool {
        guard readingBytes != nil else { return false }
        readingBytes?.append(contentsOf: addition.utf8)
        return true
    }

    @discardableResult
    mutating func deleteReadingBackward() -> Bool {
        guard var value = reading else { return false }
        if !value.isEmpty { value.removeLast() }
        readingBytes = Data(value.utf8)
        return true
    }

    /// Empty reading is abandoned; an explicit empty candidate can delete the selection.
    @discardableResult
    mutating func commitReading(candidate: String? = nil) -> Bool {
        guard let readingBytes else { return false }
        if candidate == nil, readingBytes.isEmpty {
            self.readingBytes = nil
            return true
        }
        let replacement = candidate ?? String(decoding: readingBytes, as: UTF8.self)
        guard replace(selection, with: replacement) else { return false }
        self.readingBytes = nil
        return true
    }

    @discardableResult
    mutating func cancelReading() -> Bool {
        guard readingBytes != nil else { return false }
        readingBytes = nil
        return true
    }

    private mutating func move(to position: Int, extendingSelection: Bool) -> Bool {
        if !extendingSelection { anchor = position }
        cursor = position
        return true
    }

    private mutating func replace(_ selection: NSRange, with replacement: String) -> Bool {
        let source = text
        guard let range = Self.characterRange(selection, in: source) else { return false }
        let (requestedCursor, overflowed) = selection.location.addingReportingOverflow(replacement.utf16.count)
        guard !overflowed else { return false }
        var result = Data(source[..<range.lowerBound].utf8)
        result.append(contentsOf: replacement.utf8)
        result.append(contentsOf: source[range.upperBound...].utf8)
        let resultText = String(decoding: result, as: UTF8.self)
        // Inserting a joiner, or removing a separator, can join neighboring graphemes.
        let position = Self.boundaries(in: resultText).first { $0 >= requestedCursor } ?? resultText.utf16.count
        bytes = result
        anchor = position
        cursor = position
        return true
    }

    private static func characterRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        let length = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= length,
              range.length <= length - range.location else { return nil }
        let offsets = boundaries(in: text)
        guard offsets.contains(range.location), offsets.contains(range.location + range.length) else { return nil }
        return Range(range, in: text)
    }

    private static func boundaries(in text: String) -> [Int] {
        var offsets = [0]
        var position = 0
        for character in text {
            position += String(character).utf16.count
            offsets.append(position)
        }
        return offsets
    }
}
