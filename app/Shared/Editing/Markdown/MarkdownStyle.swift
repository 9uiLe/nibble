import Foundation
import SwiftUI
import UIKit

/// Semantic text styling shared by source editing and rendered blocks.
struct MarkdownStyle: Equatable, Sendable {
    var heading: Int?
    var bold = false
    var italic = false
    var code = false
    var strike = false
    var quote = false
    var link = false

    var pointSize: CGFloat {
        heading.map { [26.0, 22, 19, 17, 15, 13][min(5, max(0, $0 - 1))] } ?? 13
    }

    func applying(_ inline: InlinePresentationIntent, link: Bool) -> Self {
        var style = self
        style.bold = inline.contains(.stronglyEmphasized)
        style.italic = inline.contains(.emphasized)
        style.code = code || inline.contains(.code)
        style.strike = inline.contains(.strikethrough)
        style.link = link
        return style
    }

    @MainActor var inputAttributes: [NSAttributedString.Key: Any] {
        let weight: UIFont.Weight = heading != nil || bold ? .bold : .regular
        var font = code ? UIFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
            : UIFont.systemFont(ofSize: pointSize, weight: weight)
        if italic, let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            font = UIFont(descriptor: descriptor, size: pointSize)
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: quote ? UIColor.secondaryLabel : UIColor.label]
        if link { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if code { attributes[.backgroundColor] = UIColor.secondarySystemFill }
        return attributes
    }

    @MainActor var previewFont: Font {
        let font = Font.system(size: pointSize, weight: heading != nil || bold ? .bold : .regular,
                               design: code ? .monospaced : .default)
        return italic ? font.italic() : font
    }
}
