import UIKit

@MainActor
enum PromptTextLayout {
    enum Field { case title, body, preview }

    static func apply(to view: UITextView, field: Field, force: Bool) {
        let title = field == .title
        let metrics = UIFontMetrics(forTextStyle: title ? .title3 : .body)
        let size: CGFloat = title ? 20 : 17
        let system = UIFont.systemFont(ofSize: size, weight: title ? .semibold : .regular)
        let descriptor = system.fontDescriptor.addingAttributes([
            .cascadeList: [UIFontDescriptor(name: title ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)],
        ])
        let font = metrics.scaledFont(for: UIFont(descriptor: descriptor, size: size), compatibleWith: view.traitCollection)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = title ? 0 : max(0, metrics.scaledValue(for: 27, compatibleWith: view.traitCollection) - font.lineHeight)
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        switch field {
        case .title:
            let inset = max(0, (44 - font.lineHeight) / 2)
            view.textContainerInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
        case .body: view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        case .preview: view.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 140, right: 0)
        }
        let current = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        guard force || view.font != font || current?.lineSpacing != paragraph.lineSpacing else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor.label]
        view.font = font
        view.typingAttributes = attributes
        view.textStorage.addAttributes(attributes, range: NSRange(location: 0, length: view.textStorage.length))
    }
}
