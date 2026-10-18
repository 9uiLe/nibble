import Foundation
import SwiftUI
import UIKit

struct MarkdownStyle: Equatable, Sendable {
    var heading: Int?
    var bold = false
    var italic = false
    var code = false
    var strike = false
    var quote = false
    var link = false

    var pointSize: CGFloat {
        guard let heading else { return 15 }
        let sizes: [CGFloat] = [26, 22, 20, 18, 16, 15]
        return sizes[min(max(heading - 1, 0), sizes.count - 1)]
    }

    func applying(_ inline: InlinePresentationIntent, link: Bool) -> Self {
        var result = self
        result.bold = inline.contains(.stronglyEmphasized)
        result.italic = inline.contains(.emphasized)
        result.strike = inline.contains(.strikethrough)
        result.code = result.code || inline.contains(.code)
        result.link = link
        return result
    }

    @MainActor var inputAttributes: [NSAttributedString.Key: Any] {
        let weight: UIFont.Weight = bold || heading != nil ? .bold : .regular
        let base = code ? UIFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
                        : UIFont.systemFont(ofSize: pointSize, weight: weight)
        var descriptor = base.fontDescriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        var result: [NSAttributedString.Key: Any] = [
            .font: UIFont(descriptor: descriptor, size: pointSize),
            .foregroundColor: quote ? UIColor.secondaryLabel : UIColor.label,
            .paragraphStyle: paragraph,
        ]
        if strike { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if link { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if code { result[.backgroundColor] = UIColor.secondarySystemFill }
        return result
    }

    @MainActor var previewFont: Font {
        let font = Font.system(size: pointSize, weight: bold || heading != nil ? .bold : .regular,
                               design: code ? .monospaced : .default)
        return italic ? font.italic() : font
    }
}
