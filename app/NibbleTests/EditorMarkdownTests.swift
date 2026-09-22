import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Markdown source editing", .serialized)
    @MainActor struct EditorMarkdownTests {
        @Test func bodyParsingIdentityTracksBytesIndependentlyOfTitle() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.title = "タイトル"
            #expect(model.bodyRevision == 0)
            model.body = "か\u{3099}"
            let revision = model.bodyRevision
            model.body = "か\u{3099}"
            #expect(model.bodyRevision == revision)
            model.body = "が"
            #expect(model.bodyRevision == revision + 1)
            #expect(await model.finish(.save))
            model.body = "完了後の入力"
            #expect(model.bodyRevision == revision + 1 && model.body == "が")
        }

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
            let boldRange = (source as NSString).range(of: "太字")
            #expect((input.textStorage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont)?
                .fontDescriptor.symbolicTraits.contains(.traitBold) == true)
            #expect(Array(input.text.utf8) == Array(source.utf8))
            let selection = NSRange(location: input.textStorage.length, length: 0)
            input.selectedRange = selection
            let modes = try #require(host.find(UISegmentedControl.self))
            modes.selectedSegmentIndex = 1
            modes.sendActions(for: .valueChanged)
            try await host.wait { !input.isFirstResponder }
            #expect(host.find(MarkdownTextView.self) === input)
            #expect(input.selectedRange == selection)
            modes.selectedSegmentIndex = 0
            modes.sendActions(for: .valueChanged)
            try await host.wait { input.isFirstResponder }
            #expect(host.find(MarkdownTextView.self) === input)
            #expect(input.selectedRange == selection)
            #expect(Array(input.text.utf8) == Array(source.utf8))
            input.selectedRange = NSRange(location: input.textStorage.length, length: 0)
            input.insertText("末尾")
            #expect(input.text == source + "末尾")
            #expect(input.selectedRange.location == (input.text as NSString).length)
            try await host.wait {
                (input.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)?.pointSize == 26
            }
            input.insertText(String(repeating: "\n長文の入力と見出し **太字**", count: 35))
            try await host.wait {
                let caret = input.convert(input.caretRect(for: input.endOfDocument), to: host.window)
                return caret.minY > 0 && caret.maxY <= host.window.bounds.maxY
            }
        }

        @Test func previewHidesSyntaxAndKeepsStructureWithoutChangingSavedSource() async throws {
            let source = "# 見出し\n\n**太字**と*斜体* `code`\n\n- 一つ\n- 二つ\n\n> 引用\n\n```swift\nlet x = 1\n```\n\n[リンク](https://example.com)"
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.body = source
            let sequence = model.draft.sequence
            let parsed = await MarkdownHighlighting.parse(model.body)
            #expect(parsed.blocks.map { String($0.text.characters) } ==
                    ["見出し", "太字と斜体 code", "一つ", "二つ", "引用", "let x = 1\n", "リンク"])
            #expect(Set(parsed.blocks.map(\.id)).count == parsed.blocks.count)
            let heading = try #require(parsed.blocks.first)
            #expect(heading.heading == 1)
            #expect(MarkdownPreviewBlock.styledText(heading).runs.first?.font == .system(size: 26, weight: .bold, design: .default))
            let paragraph = try #require(parsed.blocks.dropFirst().first)
            let styled = MarkdownPreviewBlock.styledText(paragraph)
            #expect(styled.runs.first?.font == .system(size: 13, weight: .bold, design: .default))
            #expect(parsed.blocks[2].listMarker == "•" && parsed.blocks[3].listMarker == "•")
            #expect(parsed.blocks[4].quote && parsed.blocks[5].code)
            #expect(parsed.blocks.last?.text.runs.first?.link == URL(string: "https://example.com"))
            #expect(model.draft.sequence == sequence)
            #expect(await model.finish(.keep))
            let reopened = try await database.store.draft(model.draft.id)
            #expect(Array(reopened.body.utf8) == Array(source.utf8))
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
            for source in ["", "**未完成"] {
                let view = MarkdownTextView()
                view.text = source
                view.apply(await MarkdownHighlighting.parse(source))
                #expect(Array(view.text.utf8) == Array(source.utf8))
            }
        }

        @Test(arguments: [("\n", ""), ("\n", "前\0 "), ("\r", "前\0 "), ("\r\n", "前\0 "), ("\n\r", "前\0 ")])
        func formattingUsesOriginalCoordinates(lineBreak: String, prefix: String) async throws {
            let source = "# 日本語 👩🏽‍💻" + lineBreak + lineBreak + prefix + "**太字** *斜体* `値` か\u{3099}"
            let highlights = await MarkdownHighlighting.parse(source)
            let heading = try #require(highlights.spans.first { $0.heading == 1 })
            let bold = try #require(highlights.spans.first { $0.bold })
            let italic = try #require(highlights.spans.first { $0.italic })
            let code = try #require(highlights.spans.first { $0.code })
            let original = source as NSString
            #expect(original.substring(with: heading.range) == "日本語 👩🏽‍💻")
            #expect(original.substring(with: bold.range) == "太字")
            #expect(original.substring(with: italic.range) == "斜体")
            #expect(original.substring(with: code.range) == "値")
            let view = MarkdownTextView()
            view.text = source
            view.selectedRange = NSRange(location: original.length, length: 0)
            view.apply(highlights)
            #expect(Array(view.text.utf8) == Array(source.utf8))
            #expect(view.selectedRange == NSRange(location: original.length, length: 0))
        }
    }
}
