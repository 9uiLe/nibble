import AppMacros
import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Rebuilt original-text editor", .serialized)
    @MainActor struct EditorMarkdownTests {
        @Test func parsedSpansUseOriginalUTF16Positions() async throws {
            let source = "# がか\u{3099}👩🏽‍💻\r\n**太字**\r*斜体*\n\0\u{0060}code\u{0060} ~~取消~~ [参照](https://example.com)"
            let parsed = await MarkdownDocument.parse(source)
            #expect(SnippetText.hasSameBytes(parsed.source, source))
            #expect(parsed.previewBlocks.contains { $0.style.heading == 1 })
            let cases = [
                ("太字", parsed.sourceSpans.filter(\.style.bold)),
                ("斜体", parsed.sourceSpans.filter(\.style.italic)),
                ("code", parsed.sourceSpans.filter(\.style.code)),
                ("取消", parsed.sourceSpans.filter(\.style.strike)),
                ("参照", parsed.sourceSpans.filter(\.style.link)),
            ]
            for (word, spans) in cases {
                #expect(spans.contains { (source as NSString).substring(with: $0.range).contains(word) })
            }
            for span in parsed.sourceSpans { #expect(NSMaxRange(span.range) <= source.utf16.count) }
            #expect(parsed.previewBlocks.map { String($0.text.characters) }.joined().contains("太字"))
        }

        @Test func previewIncludesListsQuotesAndFencedCode() async {
            let source = "- **一**\n- 二\n\n> 引用\n\n~~~swift\nlet x = 1\n~~~"
            let parsed = await MarkdownDocument.parse(source)
            #expect(parsed.previewBlocks.filter { $0.listMarker != nil }.count == 2)
            #expect(parsed.previewBlocks.contains { $0.style.quote })
            #expect(parsed.previewBlocks.contains { $0.style.code })
            #expect(SnippetText.hasSameBytes(source, parsed.source))
        }

        @Test func stylingPreservesBytesSelectionAndComposition() async throws {
            let view = MarkdownSourceTextView()
            let source = "**か\u{3099}👩🏽‍💻**\r\n\0末尾\t "
            view.text = source
            let selection = (source as NSString).range(of: "末尾")
            view.selectedRange = selection
            view.apply(await MarkdownDocument.parse(source))
            #expect(SnippetText.hasSameBytes(view.text, source))
            #expect(view.selectedRange == selection)
            view.setMarkedText("へんかん", selectedRange: NSRange(location: 4, length: 0))
            let composed = view.text ?? ""
            view.invalidateStyling()
            view.apply(await MarkdownDocument.parse(composed))
            #expect(SnippetText.hasSameBytes(view.text, composed))
            #expect(view.markedTextRange != nil)
            view.unmarkText()
            view.apply(await MarkdownDocument.parse(composed))
            #expect(SnippetText.hasSameBytes(view.text, composed))
        }

        @Test func mountedModeSwitchRetainsTheInputAndItsUndoHistory() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.body = "**原文**"
            let host = try ViewTestHost()
            defer { host.close() }
            host.show(AnyView(MarkdownTestSurface(model: model)))
            try await host.wait { host.find(MarkdownSourceTextView.self) != nil }
            let original = try #require(host.find(MarkdownSourceTextView.self))
            original.becomeFirstResponder()
            original.selectedRange = NSRange(location: original.text.utf16.count, length: 0)
            original.insertText("続き")
            try await host.wait { model.body.hasSuffix("続き") }
            let undo = original.undoManager
            let canUndo = undo?.canUndo
            #expect(canUndo == true)
            let picker = try #require(host.find(UISegmentedControl.self))
            picker.selectedSegmentIndex = 1
            picker.sendActions(for: .valueChanged)
            try await host.wait { !original.isFirstResponder }
            picker.selectedSegmentIndex = 0
            picker.sendActions(for: .valueChanged)
            try await host.wait { original.isFirstResponder }
            #expect(host.find(MarkdownSourceTextView.self) === original)
            #expect(original.undoManager === undo)
            #expect(original.undoManager?.canUndo == canUndo)
            #expect(SnippetText.hasSameBytes(model.body, "**原文**続き"))
            undo?.undo()
            try await host.wait { SnippetText.hasSameBytes(model.body, "**原文**") }
            undo?.redo()
            try await host.wait { SnippetText.hasSameBytes(model.body, "**原文**続き") }
        }

        @Test func nativeTitleTransferSurvivesAnalysisAndReturningToBodyRetainsUndo() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.body = "原文"
            let focus = MarkdownFocusProbe()
            let host = try ViewTestHost()
            defer { host.close() }
            host.show(AnyView(MarkdownFocusTestSurface(model: model, probe: focus)))
            try await host.wait { host.find(MarkdownSourceTextView.self)?.isFirstResponder == true && focus.value == .body }
            let original = try #require(host.find(MarkdownSourceTextView.self))
            let title = try #require(host.find(UITextField.self))

            // Start with UIKit's transfer, before SwiftUI publishes the title's focus.
            let acceptedTitle = title.becomeFirstResponder()
            #expect(acceptedTitle)
            title.insertText("題名")
            try await host.wait { title.isFirstResponder && focus.value == .title && model.title == "題名" }
            let parsedSource = "# 解析後"
            model.body = parsedSource
            try await host.wait {
                guard SnippetText.hasSameBytes(original.text, parsedSource),
                      let font = original.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont else { return false }
                return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            }
            #expect(title.isFirstResponder && focus.value == .title)
            #expect(!original.isFirstResponder)

            let acceptedBody = original.becomeFirstResponder()
            #expect(acceptedBody)
            try await host.wait { original.isFirstResponder && focus.value == .body }
            #expect(host.find(MarkdownSourceTextView.self) === original)
            original.selectedRange = NSRange(location: parsedSource.utf16.count, length: 0)
            original.insertText("追記")
            let edited = parsedSource + "追記"
            try await host.wait { SnippetText.hasSameBytes(model.body, edited) }
            let undo = try #require(original.undoManager)
            #expect(undo.canUndo)
            let selection = original.selectedRange

            let acceptedSecondTitle = title.becomeFirstResponder()
            #expect(acceptedSecondTitle)
            try await host.wait { title.isFirstResponder && focus.value == .title }
            let acceptedSecondBody = original.becomeFirstResponder()
            #expect(acceptedSecondBody)
            try await host.wait { original.isFirstResponder && focus.value == .body }
            #expect(host.find(MarkdownSourceTextView.self) === original)
            #expect(original.selectedRange == selection)
            #expect(original.undoManager === undo && undo.canUndo)
            undo.undo()
            try await host.wait { SnippetText.hasSameBytes(model.body, parsedSource) }
            undo.redo()
            try await host.wait { SnippetText.hasSameBytes(model.body, edited) }
        }

        @Test func completedKeyboardDismissalCannotReclaimBodyFocusOnAnalysisUpdates() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.body = "原文"
            let focus = MarkdownFocusProbe()
            let host = try ViewTestHost()
            defer { host.close() }
            host.show(AnyView(MarkdownFocusTestSurface(model: model, probe: focus)))
            try await host.wait { host.find(MarkdownSourceTextView.self)?.isFirstResponder == true && focus.value == .body }
            let original = try #require(host.find(MarkdownSourceTextView.self))
            let resigned = original.resignFirstResponder()
            #expect(resigned)
            try await host.wait { !original.isFirstResponder }
            // Supply the completion notification explicitly; the OS swipe is verified separately.
            NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
            try await host.wait { focus.value == nil }
            let updated = "# 終了後の解析"
            model.body = updated
            try await host.wait {
                guard SnippetText.hasSameBytes(original.text, updated),
                      let font = original.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont else { return false }
                return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            }
            #expect(!original.isFirstResponder && focus.value == nil)
            #expect(host.find(MarkdownSourceTextView.self) === original)
        }

        @Test func insertionAndFailedFinishKeepCurrentInput() async throws {
            let database = try TestDatabase()
            defer { database.removeFiles() }
            let model = EditorModel(draft: try await database.store.beginDraft(), store: database.store)
            model.body = "👩🏽‍💻前後"
            let name = try #require(VariableName("宛名"))
            let selected = (model.body as NSString).range(of: "前")
            let caret = model.insertVariable(named: name, at: selected)
            #expect(model.body == "👩🏽‍💻{{宛名}}後")
            #expect(caret?.location == selected.location + name.marker.utf16.count)
            let retained = model.body
            #expect(model.insertVariable(named: name, at: NSRange(location: Int.max, length: 1)) == nil)
            #expect(SnippetText.hasSameBytes(retained, model.body))
            model.body = " \r\n"
            #expect(await model.finish(.save) == false)
            #expect(model.phase == .editing)
            #expect(SnippetText.hasSameBytes(model.body, " \r\n"))
            #expect(await model.finish(.keep))
            let reopened = try await database.store.draft(model.draft.id)
            #expect(SnippetText.hasSameBytes(reopened.body, " \r\n"))
        }
    }
}

@Equatable
private struct MarkdownTestSurface: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @FocusState private var focus: EditorField?
    @State private var selection: NSRange?
    var body: some View {
        MarkdownEditor(model: model, focus: $focus, selection: $selection)
    }
}

@MainActor @Observable
private final class MarkdownFocusProbe {
    var value: EditorField?
}

@Equatable
private struct MarkdownFocusTestSurface: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let probe: MarkdownFocusProbe
    @FocusState private var focus: EditorField?
    @State private var selection: NSRange?

    var body: some View {
        @Bindable var editor = model
        VStack {
            MarkdownEditor(model: model, focus: $focus, selection: $selection)
            TextField("タイトル", text: $editor.title)
                .focused($focus, equals: .title)
                .textFieldStyle(.roundedBorder)
        }
        .onAppear { focus = .body }
        .onChange(of: focus, initial: true) { probe.value = focus }
    }
}
