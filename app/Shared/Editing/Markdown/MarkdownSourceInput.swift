import AppMacros
import SwiftUI
import UIKit

@Equatable(.mainActor)
struct MarkdownSourceInput: UIViewRepresentable {
    private let inputRevision = UUID()
    @Binding var text: String
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @Binding var selection: NSRange?
    let document: MarkdownDocument
    let editing: Bool

    func makeUIView(context: Context) -> MarkdownSourceTextView {
        let input = MarkdownSourceTextView()
        input.delegate = context.coordinator
        context.coordinator.attach(input)
        input.backgroundColor = .clear
        input.isScrollEnabled = false
        input.textContainerInset = .zero
        input.textContainer.lineFragmentPadding = 0
        input.typingAttributes = MarkdownStyle().inputAttributes
        input.adjustsFontForContentSizeCategory = false
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.smartDashesType = .no
        input.smartQuotesType = .no
        input.smartInsertDeleteType = .no
        input.accessibilityIdentifier = "editor.body"
        input.accessibilityLabel = "本文"
        input.accessibilityHint = "Markdown記号も空白と改行も、そのまま保存します。"
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return input
    }

    func updateUIView(_ input: MarkdownSourceTextView, context: Context) {
        context.coordinator.connection = self
        context.coordinator.synchronizing = true
        defer { context.coordinator.synchronizing = false }
        input.isEditable = context.environment.isEnabled && editing
        if input.markedTextRange == nil {
            if !SnippetText.hasSameBytes(input.text, text) {
                let desired = selection ?? input.selectedRange
                input.text = text
                input.invalidateStyling()
                let start = max(0, min(desired.location, input.textStorage.length))
                input.selectedRange = NSRange(location: start,
                    length: max(0, min(desired.length, input.textStorage.length - start)))
            }
            if let selection, selection != input.selectedRange,
               selection.location >= 0, selection.length >= 0,
               selection.location <= input.textStorage.length,
               selection.length <= input.textStorage.length - selection.location {
                input.selectedRange = selection
            }
            input.apply(document)
        }
        let requested = focus.wrappedValue == .body && input.isEditable
        input.wantsFocus = requested
        if context.coordinator.requestedFocus != requested {
            context.coordinator.requestedFocus = requested
            if requested && input.window != nil && !input.isFirstResponder { input.becomeFirstResponder() }
            if !requested && input.isFirstResponder { input.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownSourceTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(180, measured.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(connection: self) }

    static func dismantleUIView(_ input: MarkdownSourceTextView, coordinator: Coordinator) {
        input.wantsFocus = false
        input.delegate = nil
        coordinator.detach()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var connection: MarkdownSourceInput
        var synchronizing = false
        var requestedFocus: Bool?
        private weak var input: UITextView?

        init(connection: MarkdownSourceInput) { self.connection = connection }

        func attach(_ input: UITextView) {
            self.input = input
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden(_:)),
                                                   name: UIResponder.keyboardDidHideNotification, object: nil)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
            input = nil
        }

        @objc private func keyboardHidden(_: Notification) {
            guard !synchronizing, let input, !input.isFirstResponder, connection.focus.wrappedValue == .body else { return }
            connection.focus.wrappedValue = nil
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !synchronizing, connection.focus.wrappedValue != .body else { return }
            connection.focus.wrappedValue = .body
        }
        func textViewDidChange(_ textView: UITextView) {
            guard !synchronizing else { return }
            connection.text = textView.text
            (textView as? MarkdownSourceTextView)?.invalidateStyling()
            textView.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !synchronizing, textView.markedTextRange == nil,
                  connection.selection != textView.selectedRange else { return }
            connection.selection = textView.selectedRange
        }
    }
}
