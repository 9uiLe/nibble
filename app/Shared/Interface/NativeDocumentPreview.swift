import AppMacros
import SwiftUI
import UIKit

@MainActor @Equatable(.mainActor)
struct NativeDocumentPreview: UIViewRepresentable {
    enum Style { case document, prompt }
    private let inputRevision = UUID()
    let text: String
    let identifier: String
    let style: Style

    init(text: String, identifier: String, style: Style = .document) {
        self.text = text
        self.identifier = identifier
        self.style = style
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.dataDetectorTypes = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        configure(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: proposal.height ?? 240)
    }

    private func configure(_ view: UITextView) {
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = style == .prompt ? "プロンプトの全文" : "使う文章の全文"
        view.accessibilityHint = "上下にスクロールして全文を確認できます"
        let changed = !text.utf8.elementsEqual((view.text ?? "").utf8)
        if changed {
            view.text = text
            view.setContentOffset(.zero, animated: false)
        }
        if style == .prompt { PromptTextLayout.apply(to: view, field: .preview, force: changed) }
    }
}
