import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
@testable import Nibble

extension UIIntegrationTests {
    @Suite("Mounted native document input boundary", .serialized)
    @MainActor
    struct NativeDocumentFieldTests {
        @Test func readOnlyPreviewKeepsExactTextAndScrollsToTheEndWithoutAnUnboundedRow() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let original = String(repeating: "原文 **か\u{3099}** 👩🏽‍💻\r\n", count: 400) + "\0末尾"
            host.show(AnyView(NativeDocumentPreview(text: original, identifier: "native.preview").frame(height: 200)))
            try await host.wait { host.find(UITextView.self)?.text.utf8.elementsEqual(original.utf8) == true }
            let preview = try #require(host.find(UITextView.self))
            #expect(!preview.isEditable && preview.isSelectable && preview.isScrollEnabled)
            #expect(preview.textLayoutManager != nil)
            #expect(preview.dataDetectorTypes.isEmpty)
            #expect(preview.bounds.height == 200)
            preview.scrollRangeToVisible(NSRange(location: original.utf16.count, length: 0))
            try await host.wait { preview.contentOffset.y > 0 }
            #expect(preview.text.utf8.elementsEqual(original.utf8))
            let replacement = "差し替え済み\r\nか\u{3099}\0👩🏽‍💻"
            host.show(AnyView(NativeDocumentPreview(text: replacement, identifier: "native.preview").frame(height: 200)))
            try await host.wait { preview.text.utf8.elementsEqual(replacement.utf8) && preview.contentOffset.y == 0 }
            #expect(host.find(UITextView.self) === preview)
            #expect(!preview.isEditable)
        }

        @Test func replacingAnEqualBindingMovesSubsequentNativeEditsToTheCurrentDestination() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let first = NativeFieldValue("同じ本文")
            let replacement = NativeFieldValue("同じ本文")
            host.show(AnyView(NativeDocumentField(text: first.binding, composing: first.composition,
                                                identifier: "native.binding", label: "本文の接続").frame(height: 180)))
            try await host.wait { host.find(UITextView.self)?.accessibilityLabel == "本文の接続" }
            let input = try #require(host.find(UITextView.self))
            #expect(input.becomeFirstResponder())
            host.show(AnyView(NativeDocumentField(text: replacement.binding, composing: replacement.composition,
                                                identifier: "native.binding", label: "本文の接続").frame(height: 180)))
            // All visible/configuration inputs remain equal. Only the Binding
            // destination changes; wait for the mounted SwiftUI update to render.
            try await settleNativeFieldHost(host)
            #expect(host.find(UITextView.self) === input)
            input.selectedRange = NSRange(location: input.text.utf16.count, length: 0)
            input.insertText("・追記👩🏽‍💻")
            try await host.wait { replacement.value.utf8.elementsEqual("同じ本文・追記👩🏽‍💻".utf8) }
            #expect(first.value == "同じ本文")
            #expect(replacement.composing == false)
            replacement.value = "今の接続からの更新"
            host.show(AnyView(NativeDocumentField(text: replacement.binding, composing: replacement.composition,
                                                identifier: "native.binding", label: "現在値の更新").frame(height: 180)))
            try await host.wait { input.text == "今の接続からの更新" }
            first.value = "古い接続だけを変更"
            host.show(AnyView(NativeDocumentField(text: replacement.binding, composing: replacement.composition,
                                                identifier: "native.binding", label: "接続の再確認").frame(height: 180)))
            try await host.wait { input.accessibilityLabel == "接続の再確認" }
            #expect(input.text == "今の接続からの更新")
        }

        @Test func aMountedSwiftUIUpdateDoesNotReplaceAMarkedNativeRange() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let value = NativeFieldValue("前後")
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.marked", label: "変換前").frame(height: 180)))
            try await host.wait { host.find(UITextView.self) != nil }
            let input = try #require(host.find(UITextView.self))
            #expect(input.becomeFirstResponder())
            input.selectedRange = NSRange(location: 1, length: 0)
            // This injects UIKit's marked-text state. OS Japanese IME operation is
            // verified separately; this test covers the mounted update boundary.
            input.setMarkedText("へんかん", selectedRange: NSRange(location: 4, length: 0))
            input.delegate?.textViewDidChange?(input)
            let marked = try #require(input.markedTextRange)
            let before = input.text ?? ""
            let selectedBefore = input.selectedRange
            let markedStart = input.offset(from: input.beginningOfDocument, to: marked.start)
            let markedLength = input.offset(from: marked.start, to: marked.end)
            #expect(value.composing)
            value.value = "外部から届いた更新"
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.marked", label: "変換中の更新").frame(height: 180)))
            try await host.wait { input.accessibilityLabel == "変換中の更新" }
            let retained = try #require(input.markedTextRange)
            #expect(input.text.utf8.elementsEqual(before.utf8))
            #expect(input.selectedRange == selectedBefore)
            #expect(input.offset(from: input.beginningOfDocument, to: retained.start) == markedStart)
            #expect(input.offset(from: retained.start, to: retained.end) == markedLength)
            #expect(host.find(UITextView.self) === input)
            // UIKit may discard the synthetic marked segment when unmarked.
            // The binding must follow the actual native result, including cancellation.
            input.unmarkText()
            let nativeResult = input.text ?? ""
            input.delegate?.textViewDidChange?(input)
            try await host.wait { !value.composing && value.value.utf8.elementsEqual(nativeResult.utf8) }
            #expect(!nativeResult.utf8.elementsEqual("外部から届いた更新".utf8))
        }

        @Test func unicodeSelectionAndNativeReplacementRoundTripThroughTheMountedBinding() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let original = "前👩🏽‍💻か\u{3099}\r\n置換する文字\0後"
            let value = NativeFieldValue(original)
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.selection", label: "原文").frame(height: 180)))
            try await host.wait { host.find(UITextView.self)?.text.utf8.elementsEqual(original.utf8) == true }
            let input = try #require(host.find(UITextView.self))
            #expect(input.becomeFirstResponder())
            let selection = (original as NSString).range(of: "置換する文字")
            input.selectedRange = selection
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.selection", label: "選択の保持").frame(height: 180)))
            try await host.wait { input.accessibilityLabel == "選択の保持" }
            #expect(input.selectedRange == selection)
            #expect(input.text.utf8.elementsEqual(original.utf8))
            input.insertText("訂正🇯🇵")
            let expected = (original as NSString).replacingCharacters(in: selection, with: "訂正🇯🇵")
            try await host.wait { value.value.utf8.elementsEqual(expected.utf8) }
            let caret = NSRange(location: selection.location + "訂正🇯🇵".utf16.count, length: 0)
            #expect(input.selectedRange == caret)
            #expect(!value.composing)
            value.value = expected + "末尾"
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.selection", label: "末尾の更新").frame(height: 180)))
            try await host.wait { input.text.utf8.elementsEqual((expected + "末尾").utf8) }
            #expect(input.selectedRange == caret)
            #expect(host.find(UITextView.self) === input)
            #expect(input.resignFirstResponder())
            #expect(value.value.utf8.elementsEqual((expected + "末尾").utf8))
        }

        @Test func shrinkingTheBoundTextMovesAnInvalidUnicodeSelectionToTheNewEnd() async throws {
            let host = try ViewTestHost()
            defer { host.close() }
            let value = NativeFieldValue("長い👩🏽‍💻文章の末尾")
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.selection.end", label: "長い原文").frame(height: 180)))
            try await host.wait { host.find(UITextView.self) != nil }
            let input = try #require(host.find(UITextView.self))
            input.selectedRange = NSRange(location: value.value.utf16.count, length: 0)
            value.value = "か\u{3099}"
            host.show(AnyView(NativeDocumentField(text: value.binding, composing: value.composition,
                                                identifier: "native.selection.end", label: "短い原文").frame(height: 180)))
            try await host.wait { input.text.utf8.elementsEqual(value.value.utf8) }
            #expect(input.selectedRange == NSRange(location: value.value.utf16.count, length: 0))
        }
    }
}

@MainActor @Observable
private final class NativeFieldValue {
    var value: String
    var composing = false

    init(_ value: String) { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
    var composition: Binding<Bool> { Binding(get: { self.composing }, set: { self.composing = $0 }) }
}

@MainActor
private func settleNativeFieldHost(_ host: ViewTestHost) async throws {
    try await Task.sleep(for: .milliseconds(100))
    let view = try #require(host.controller.view)
    view.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
    var rendered = false
    _ = renderer.image { _ in rendered = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
    try #require(rendered, "The mounted field must render before editing its new Binding destination")
}
