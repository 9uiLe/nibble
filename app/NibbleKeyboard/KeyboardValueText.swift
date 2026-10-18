import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardValueText: View {
    private let inputRevision = UUID()
    let buffer: KeyboardValueBuffer
    let compact: Bool

    private var markedText: AttributedString {
        let source = buffer.text
        guard let range = Range(buffer.selection, in: source) else { return AttributedString(source) }
        var output = AttributedString(String(source[..<range.lowerBound]))
        switch buffer.reading {
        case .some(let reading):
            var pending = AttributedString(reading)
            pending.underlineStyle = .single
            pending.foregroundColor = .nibbleKeyboardAccent
            output += pending
            var caret = AttributedString("▏")
            caret.foregroundColor = .nibbleKeyboardAccent
            output += caret
        case .none:
            switch buffer.selection.length {
            case 0:
                var caret = AttributedString("▏")
                caret.foregroundColor = .nibbleKeyboardAccent
                output += caret
            default:
                var selection = AttributedString(String(source[range]))
                selection.backgroundColor = .nibbleKeyboardHighlight
                output += selection
            }
        }
        output += AttributedString(String(source[range.upperBound...]))
        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(markedText).font(.nibbleBody).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: compact ? 20 : 44, alignment: .leading)
                .accessibilityIdentifier("variables.valueText")
            if !compact {
                Text(buffer.reading == nil ? "縦線は入力位置、色の付いた部分は選択範囲です。" : "下線の文字は未確定です。変換候補か「文字を確定」を選べます。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
            }
        }
        .padding(compact ? 0 : 8).overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.nibbleBorder) }
    }
}
