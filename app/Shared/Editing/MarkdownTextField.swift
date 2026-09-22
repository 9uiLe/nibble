import AppMacros
import SwiftUI
import UIKit

/// UIKit exposes marked text and in-place attributes so styling never replaces
/// Japanese composition, the selection, undo history or the Markdown source.
@Equatable(.mainActor)
struct MarkdownTextField: UIViewRepresentable {
    private let inputRevision = UUID()
    @Binding var text: String
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    let highlighting: MarkdownHighlighting

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = .systemFont(ofSize: 13)
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

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        if view.isEditable != context.environment.isEnabled { view.isEditable = context.environment.isEnabled }
        if view.markedTextRange == nil {
            if !SnippetText.hasSameBytes(view.text, text) {
                let selection = view.selectedRange
                view.text = text
                view.selectedRange = NSRange(location: min(selection.location, view.textStorage.length), length: 0)
            }
            view.apply(highlighting)
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: max(180, uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextField
        var requestedFocus: Bool?
        init(_ parent: MarkdownTextField) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.focus.wrappedValue = .body }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? MarkdownTextView)?.invalidateHighlighting()
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
    }
}

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
