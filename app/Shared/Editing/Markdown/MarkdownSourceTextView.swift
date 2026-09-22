import UIKit

final class MarkdownSourceTextView: UITextView {
    var wantsFocus = false
    private var applied: MarkdownDocument?

    func invalidateStyling() { applied = nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && wantsFocus && !isFirstResponder { becomeFirstResponder() }
    }

    func apply(_ document: MarkdownDocument) {
        guard markedTextRange == nil, SnippetText.hasSameBytes(text, document.source),
              applied != document else { return }
        let selection = selectedRange
        textStorage.beginEditing()
        textStorage.setAttributes(MarkdownStyle().inputAttributes,
                                  range: NSRange(location: 0, length: textStorage.length))
        for span in document.sourceSpans where NSMaxRange(span.range) <= textStorage.length {
            textStorage.addAttributes(span.style.inputAttributes, range: span.range)
        }
        textStorage.endEditing()
        selectedRange = selection
        typingAttributes = MarkdownStyle().inputAttributes
        applied = document
        invalidateIntrinsicContentSize()
    }
}
