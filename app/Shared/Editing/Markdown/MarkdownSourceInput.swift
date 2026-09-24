import AppMacros
import SwiftUI
import UIKit

/// UIKit exposes marked text and in-place attributes so styling never replaces
/// Japanese composition, the selection, undo history or the Markdown source.
@Equatable(.mainActor)
struct MarkdownSourceInput: UIViewRepresentable {
    private let inputRevision = UUID()
    @Binding var text: String
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @Binding var selection: NSRange?
    let document: MarkdownDocument

    func makeUIView(context: Context) -> MarkdownSourceTextView {
        let view = MarkdownSourceTextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.typingAttributes = MarkdownStyle().inputAttributes
        view.textColor = .label
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.adjustsFontForContentSizeCategory = false
        view.accessibilityIdentifier = "editor.body"
        view.accessibilityLabel = "本文"
        view.accessibilityHint = "Markdownの見出し、太字、斜体、コードを入力できます。記号もそのまま保存します。"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: MarkdownSourceTextView, context: Context) {
        context.coordinator.parent = self
        if view.isEditable != context.environment.isEnabled { view.isEditable = context.environment.isEnabled }
        if view.markedTextRange == nil {
            if !SnippetText.hasSameBytes(view.text, text) {
                let desiredSelection = selection ?? view.selectedRange
                view.text = text
                let start = min(desiredSelection.location, view.textStorage.length)
                view.selectedRange = NSRange(location: start,
                                             length: min(desiredSelection.length, view.textStorage.length - start))
            } else if let selection, view.selectedRange != selection,
                      NSMaxRange(selection) <= view.textStorage.length {
                view.selectedRange = selection
            }
            view.apply(document)
        }
        // Reconcile requests once; repeated updates must not reclaim focus from the title.
        let wantsFocus = focus.wrappedValue == .body && view.isEditable
        if context.coordinator.requestedFocus != wantsFocus {
            context.coordinator.requestedFocus = wantsFocus
            view.wantsFocus = wantsFocus
            if wantsFocus {
                if view.window != nil && !view.isFirstResponder { view.becomeFirstResponder() }
            } else if view.isFirstResponder { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownSourceTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: max(180, uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownSourceInput
        var requestedFocus: Bool?
        init(_ parent: MarkdownSourceInput) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.focus.wrappedValue = .body }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? MarkdownSourceTextView)?.invalidateStyling()
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.markedTextRange == nil { parent.selection = textView.selectedRange }
        }
    }
}
