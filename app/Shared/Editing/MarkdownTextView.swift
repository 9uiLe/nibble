import UIKit

final class MarkdownTextView: UITextView {
    var wantsFocus = false
    private var applied: MarkdownHighlighting?

    func invalidateHighlighting() { applied = nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && wantsFocus && !isFirstResponder { becomeFirstResponder() }
    }

    func apply(_ highlighting: MarkdownHighlighting) {
        guard markedTextRange == nil, SnippetText.hasSameBytes(text, highlighting.source),
              applied != highlighting else { return }
        let selection = selectedRange
        textStorage.beginEditing()
        textStorage.setAttributes([.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.label],
                                  range: NSRange(location: 0, length: textStorage.length))
        for span in highlighting.spans where NSMaxRange(span.range) <= textStorage.length {
            let size: CGFloat = span.heading.map { [26.0, 22, 19, 17, 15, 13][min(5, max(0, $0 - 1))] } ?? 13
            var font = span.code ? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                : UIFont.systemFont(ofSize: size, weight: span.bold || span.heading != nil ? .bold : .regular)
            if span.italic, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                font = UIFont(descriptor: descriptor, size: size)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if span.quote { attributes[.foregroundColor] = UIColor.secondaryLabel }
            if span.link { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if span.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if span.code { attributes[.backgroundColor] = UIColor.secondarySystemFill }
            textStorage.addAttributes(attributes, range: span.range)
        }
        textStorage.endEditing()
        selectedRange = selection
        typingAttributes = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.label]
        applied = highlighting
        invalidateIntrinsicContentSize()
    }
}
