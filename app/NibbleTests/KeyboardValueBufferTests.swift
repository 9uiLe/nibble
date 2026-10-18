import Foundation
import Testing
@testable import Nibble

@Suite("Local keyboard value editing")
struct KeyboardValueBufferTests {
    @Test(arguments: ["か\u{3099}", "é", "e\u{301}", "👩🏽‍💻", "🇯🇵", "\r\n", "\0", "\t漢字\n𝄞"])
    func selectedTextCanBeReplacedWithRawUnicode(replacement: String) {
        var buffer = KeyboardValueBuffer(text: "左X右")
        let selected = buffer.select(NSRange(location: 1, length: 1))
        let replaced = buffer.replaceSelection(with: replacement)
        #expect(selected && replaced)
        #expect(Data(buffer.text.utf8) == Data(("左" + replacement + "右").utf8))
        #expect(buffer.selection == NSRange(location: 1 + replacement.utf16.count, length: 0))
    }

    @Test(arguments: [
        NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
        NSRange(location: 2, length: 0), NSRange(location: 3, length: 1),
        NSRange(location: 9, length: 0), NSRange(location: 11, length: 0),
        NSRange(location: 8, length: 1), NSRange(location: 14, length: 1),
        NSRange(location: 15, length: 0), NSRange(location: 0, length: Int.max),
        NSRange(location: NSNotFound, length: 0)
    ])
    func invalidUTF16SelectionsAreRejectedWithoutMutation(range: NSRange) {
        let raw = "A👩🏽‍💻e\u{301}\r\n\0Z"
        var buffer = KeyboardValueBuffer(text: raw)
        let before = buffer
        let accepted = buffer.select(range)
        #expect(!accepted && buffer == before)
        #expect(KeyboardValueBuffer(text: raw, selection: range) == nil)
    }

    @Test func replacingAcrossWholeGraphemesRetainsUntouchedBytes() {
        var buffer = KeyboardValueBuffer(text: "A👩🏽‍💻e\u{301}\r\n\0Z")
        let selected = buffer.select(NSRange(location: 1, length: 11))
        let replaced = buffer.replaceSelection(with: "か\u{3099}")
        #expect(selected && replaced)
        #expect(Data(buffer.text.utf8) == Data("Aか\u{3099}\0Z".utf8))
        #expect(buffer.selection == NSRange(location: 3, length: 0))
    }

    @Test(arguments: [true, false])
    func restoredSelectionCollapsesAtTheRequestedEdgeWithoutSkippingText(left: Bool) throws {
        let raw = "A👩🏽‍💻B"
        var buffer = try #require(KeyboardValueBuffer(text: raw, selection: NSRange(location: 1, length: 7)))
        switch left {
        case true: buffer.moveLeft()
        case false: buffer.moveRight()
        }
        #expect(Data(buffer.text.utf8) == Data(raw.utf8))
        #expect(buffer.selection == NSRange(location: left ? 1 : 8, length: 0))
    }

    @Test func shiftSelectionRetainsItsAnchorAcrossDirectionChanges() {
        var buffer = KeyboardValueBuffer(text: "A👩🏽‍💻e\u{301}\r\n\0Z")
        buffer.moveToStart()
        buffer.moveRight()
        buffer.moveRight(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 1, length: 7))
        buffer.moveRight(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 1, length: 9))
        buffer.moveLeft(extendingSelection: true)
        buffer.moveLeft(extendingSelection: true)
        buffer.moveLeft(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 0, length: 1))
        buffer.moveRight()
        #expect(buffer.selection == NSRange(location: 1, length: 0))
        buffer.moveLeft()
        buffer.moveToEnd(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 0, length: 14))
        buffer.moveToStart()
        buffer.moveToEnd()
        buffer.moveToStart(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 0, length: 14))
        buffer.moveRight(extendingSelection: true)
        #expect(buffer.selection == NSRange(location: 1, length: 13))
    }

    @Test func deletionsTreatEmojiCombiningTextCRLFAndNullAsWholeCharacters() {
        var buffer = KeyboardValueBuffer(text: "A👩🏽‍💻e\u{301}\r\n\0Z")
        buffer.moveToStart()
        buffer.deleteBackward()
        #expect(Data(buffer.text.utf8) == Data("A👩🏽‍💻e\u{301}\r\n\0Z".utf8))
        buffer.deleteForward()
        buffer.deleteForward()
        #expect(Data(buffer.text.utf8) == Data("e\u{301}\r\n\0Z".utf8))
        buffer.moveToEnd()
        buffer.deleteForward()
        buffer.deleteBackward()
        buffer.deleteBackward()
        #expect(Data(buffer.text.utf8) == Data("e\u{301}\r\n".utf8))
        buffer.deleteBackward()
        #expect(Data(buffer.text.utf8) == Data("e\u{301}".utf8))
        buffer.deleteBackward()
        #expect(buffer.text.isEmpty && buffer.selection == NSRange(location: 0, length: 0))
    }

    @Test func selectionDeletionAndSelectAllDoNotLeavePartialText() {
        var buffer = KeyboardValueBuffer(text: "前👩🏽‍💻後")
        buffer.select(NSRange(location: 1, length: 7))
        buffer.deleteBackward()
        #expect(buffer.text == "前後" && buffer.selection == NSRange(location: 1, length: 0))
        buffer.selectAll()
        buffer.deleteForward()
        #expect(buffer.text.isEmpty && buffer.selection == NSRange(location: 0, length: 0))
    }

    @Test func editsThatJoinNeighborsKeepBytesAndMoveTheCaretPastTheJoinedCharacter() {
        var emoji = KeyboardValueBuffer(text: "👩💻")
        emoji.select(NSRange(location: 2, length: 0))
        emoji.replaceSelection(with: "\u{200D}")
        #expect(Data(emoji.text.utf8) == Data("👩‍💻".utf8))
        #expect(emoji.selection == NSRange(location: 5, length: 0))
        emoji.moveLeft()
        #expect(emoji.selection == NSRange(location: 0, length: 0))
        emoji.moveRight()
        emoji.deleteBackward()
        #expect(emoji.text.isEmpty)

        var combining = KeyboardValueBuffer(text: "\u{301}x")
        combining.moveToStart()
        combining.replaceSelection(with: "e")
        #expect(Data(combining.text.utf8) == Data("e\u{301}x".utf8))
        #expect(combining.selection == NSRange(location: 2, length: 0))

        var newline = KeyboardValueBuffer(text: "a\rX\nb")
        newline.select(NSRange(location: 2, length: 1))
        newline.replaceSelection(with: "")
        #expect(Data(newline.text.utf8) == Data("a\r\nb".utf8))
        #expect(newline.selection == NSRange(location: 3, length: 0))
        newline.deleteBackward()
        #expect(newline.text == "ab")
    }

    @Test func candidateCommitReplacesTheOriginalSelectionOnce() {
        var buffer = KeyboardValueBuffer(text: "左👩🏽‍💻右")
        buffer.select(NSRange(location: 1, length: 7))
        buffer.beginReading("に")
        buffer.appendReading("ほん")
        buffer.setReading("にほんご")
        #expect(buffer.text == "左👩🏽‍💻右" && buffer.reading == "にほんご")
        #expect(buffer.selection == NSRange(location: 1, length: 7))
        let committed = buffer.commitReading(candidate: "日本語")
        let once = buffer
        let repeated = buffer.commitReading(candidate: "別の候補")
        #expect(committed && !repeated && buffer == once)
        #expect(buffer.text == "左日本語右" && buffer.reading == nil)
        #expect(buffer.selection == NSRange(location: 4, length: 0))
    }

    @Test func cancelRestoresTheExactValueSelectionAndShiftAnchor() {
        var buffer = KeyboardValueBuffer(text: "e\u{301}👩🏽‍💻\0")
        buffer.moveToStart(extendingSelection: true)
        buffer.moveRight(extendingSelection: true)
        let original = buffer
        buffer.beginReading("か\u{3099}")
        buffer.appendReading("\r\n")
        let cancelled = buffer.cancelReading()
        #expect(cancelled && buffer == original)
    }

    @Test func activeReadingRejectsOtherEditsAndAnotherBeginWithoutChangingAnything() {
        var buffer = KeyboardValueBuffer(text: "原文")
        buffer.beginReading("未確定")
        let original = buffer
        let accepted = [buffer.select(NSRange(location: 0, length: 0)),
                        buffer.replaceSelection(with: "差替"), buffer.moveLeft(), buffer.moveRight(),
                        buffer.moveToStart(), buffer.moveToEnd(), buffer.selectAll(),
                        buffer.deleteBackward(), buffer.deleteForward(), buffer.beginReading("上書き")]
        #expect(accepted.allSatisfy { !$0 } && buffer == original)
    }

    @Test func readingCorrectionPreservesGraphemesAndAnEmptyCommitDoesNotDeleteTheSelection() {
        var buffer = KeyboardValueBuffer(text: "残す")
        buffer.selectAll()
        let original = buffer
        buffer.beginReading("e\u{301}👩🏽‍💻\r\n\0")
        buffer.deleteReadingBackward()
        #expect(Data((buffer.reading ?? "").utf8) == Data("e\u{301}👩🏽‍💻\r\n".utf8))
        buffer.deleteReadingBackward()
        buffer.deleteReadingBackward()
        #expect(Data((buffer.reading ?? "").utf8) == Data("e\u{301}".utf8))
        buffer.deleteReadingBackward()
        buffer.commitReading()
        #expect(buffer == original)
        buffer.beginReading()
        buffer.commitReading(candidate: "")
        #expect(buffer.text.isEmpty && buffer.reading == nil)
    }

    @Test func rawReadingCommitAndSynthesizedEqualityKeepCanonicalSpellingsDistinct() {
        var composed = KeyboardValueBuffer(text: "é")
        var decomposed = KeyboardValueBuffer(text: "e\u{301}")
        composed.moveToStart()
        decomposed.moveToStart()
        #expect(composed != decomposed)

        var first = KeyboardValueBuffer()
        var second = KeyboardValueBuffer()
        first.beginReading("é")
        second.beginReading("e\u{301}")
        #expect(first != second)
        second.commitReading()
        #expect(Data(second.text.utf8) == Data("e\u{301}".utf8))
        let original = second
        let rejected = [second.appendReading("x"), second.setReading("x"),
                        second.deleteReadingBackward(), second.cancelReading(), second.commitReading()]
        #expect(rejected.allSatisfy { !$0 } && second == original)
    }
}
