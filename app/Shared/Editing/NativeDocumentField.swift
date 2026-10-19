import AppMacros
import SwiftUI
import UIKit

@MainActor
@Equatable(.mainActor)
struct NativeDocumentField: UIViewRepresentable {
    private let inputRevision = UUID()
    @Binding private var text: String
    @Binding private var composing: Bool
    let identifier: String
    let label: String
    let singleLine: Bool

    init(text: Binding<String>, composing: Binding<Bool>, identifier: String, label: String, singleLine: Bool = false) {
        _text = text
        _composing = composing
        self.identifier = identifier
        self.label = label
        self.singleLine = singleLine
    }

    func makeUIView(context: Context) -> UITextView {
        let input = UITextView()
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.textColor = .label
        input.backgroundColor = .secondarySystemBackground
        input.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        input.autocapitalizationType = .none
        input.autocorrectionType = .no
        input.smartDashesType = .no
        input.smartQuotesType = .no
        input.smartInsertDeleteType = .no
        input.isScrollEnabled = true
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        input.accessibilityIdentifier = identifier
        input.accessibilityLabel = label
        if !text.utf8.elementsEqual((input.text ?? "").utf8) {
            input.text = text
        }
        input.delegate = context.coordinator
        return input
    }

    func updateUIView(_ input: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.connection = self
        coordinator.synchronizing = true
        defer { coordinator.synchronizing = false }
        input.accessibilityIdentifier = identifier
        input.accessibilityLabel = label
        input.isEditable = context.environment.isEnabled
        guard input.markedTextRange == nil, !text.utf8.elementsEqual((input.text ?? "").utf8) else { return }
        let selection = input.selectedRange
        input.text = text
        if Range(selection, in: text) != nil {
            input.selectedRange = selection
        } else {
            input.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
        input.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        if let height = proposal.height, height > 0, height.isFinite {
            return CGSize(width: width, height: height)
        }
        if singleLine {
            let lineHeight = (uiView.font ?? .preferredFont(forTextStyle: .body)).lineHeight
            return CGSize(width: width, height: lineHeight + uiView.textContainerInset.top + uiView.textContainerInset.bottom)
        }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(connection: self) }

    static func dismantleUIView(_ input: UITextView, coordinator: Coordinator) {
        input.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var connection: NativeDocumentField
        var synchronizing = false

        init(connection: NativeDocumentField) {
            self.connection = connection
        }

        func textViewDidChange(_ textView: UITextView) {
            publish(textView)
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publish(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            publish(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            publish(textView)
        }

        private func publish(_ input: UITextView) {
            guard !synchronizing else { return }
            let isComposing = input.markedTextRange != nil
            if isComposing && !connection.composing {
                connection.composing = true
            }
            let current = input.text ?? ""
            if !connection.text.utf8.elementsEqual(current.utf8) {
                connection.text = current
            }
            if !isComposing && connection.composing {
                connection.composing = false
            }
        }
    }
}
