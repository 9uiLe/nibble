import UIKit

final class MarkdownSourceTextView: UITextView {
    var wantsFocus = false
    private var styledSource: String?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, wantsFocus, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    func invalidateStyling() { styledSource = nil }

    func apply(_ document: MarkdownDocument) {
        guard markedTextRange == nil, SnippetText.hasSameBytes(document.source, text) else { return }
        if let styledSource, SnippetText.hasSameBytes(styledSource, document.source) { return }
        let retainedSelection = selectedRange
        textStorage.beginEditing()
        textStorage.setAttributes(MarkdownStyle().inputAttributes, range: NSRange(location: 0, length: textStorage.length))
        for span in document.sourceSpans {
            guard span.range.location >= 0, span.range.length >= 0,
                  span.range.location <= textStorage.length,
                  span.range.length <= textStorage.length - span.range.location else { continue }
            textStorage.addAttributes(span.style.inputAttributes, range: span.range)
        }
        textStorage.endEditing()
        selectedRange = retainedSelection
        typingAttributes = MarkdownStyle().inputAttributes
        styledSource = document.source
        invalidateIntrinsicContentSize()
    }
}
