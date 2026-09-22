import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Markdown source editing", .serialized)
    @MainActor struct EditorMarkdownTests {
        @Test func newEditorFocusesTheMountedMarkdownInput() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let draft = try await database.store.beginDraft()
            let host = try RiveTestHost()
            defer { host.close() }
            host.window.makeKeyAndVisible()
            host.show(AnyView(SnippetEditor(draft: draft, store: database.store)))
            try await host.wait { host.find(MarkdownTextView.self)?.isFirstResponder == true }
            let input = try #require(host.find(MarkdownTextView.self))
            let source = "# 入力した見出し\n\n**太字** 👩🏽‍💻 か\u{3099}"
            input.insertText(source)
            try await host.wait {
                (input.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)?.pointSize == 26
            }
            #expect(Array(input.text.utf8) == Array(source.utf8))
            input.selectedRange = NSRange(location: input.textStorage.length, length: 0)
            input.insertText("末尾")
            #expect(input.text == source + "末尾")
            #expect(input.selectedRange.location == (input.text as NSString).length)
            input.insertText(String(repeating: "\n長文の入力と見出し **太字**", count: 35))
            try await host.wait {
                let caret = input.convert(input.caretRect(for: input.endOfDocument), to: host.window)
                return caret.minY > 0 && caret.maxY <= host.window.bounds.maxY
            }
        }
        @Test func formattingPreservesSourceSelectionAndComposition() async throws {
            let source = "# 日本語 👩🏽‍💻\n\n**太字** *italic* `code`\n\nか\u{3099}\t  \n\n```swift\nlet x = 1\n```"
            let highlights = await MarkdownHighlighting.parse(source)
            let title = try #require(highlights.spans.first { $0.heading == 1 })
            #expect((source as NSString).substring(with: title.range) == "日本語 👩🏽‍💻")
            let bold = try #require(highlights.spans.first { $0.bold })
            #expect((source as NSString).substring(with: bold.range) == "太字")
            let view = MarkdownTextView()
            view.text = source
            view.selectedRange = NSRange(location: 4, length: 2)
            view.apply(highlights)
            #expect(Array(view.text.utf8) == Array(source.utf8))
            #expect(view.selectedRange == NSRange(location: 4, length: 2))
            let titleFont = try #require(view.textStorage.attribute(.font, at: title.range.location, effectiveRange: nil) as? UIFont)
            #expect(titleFont.pointSize == 26)
            let boldFont = try #require(view.textStorage.attribute(.font, at: bold.range.location, effectiveRange: nil) as? UIFont)
            #expect(boldFont.fontDescriptor.symbolicTraits.contains(.traitBold))
            view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
            let composed = view.text
            let markedRange = view.markedTextRange
            view.apply(await MarkdownHighlighting.parse(view.text))
            #expect(view.text == composed)
            #expect((view.markedTextRange == nil) == (markedRange == nil))
        }

        @Test func plainOrIncompleteMarkdownIsStillEditableSource() async throws {
            for source in ["", "**未完成", "\\*装飾しない*", "  日本語\u{0}\r\nか\u{3099}  "] {
                let view = MarkdownTextView()
                view.text = source
                view.apply(await MarkdownHighlighting.parse(source))
                #expect(Array(view.text.utf8) == Array(source.utf8))
            }
        }
    }
}
