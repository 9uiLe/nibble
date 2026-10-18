import Foundation

struct KeyboardValueKey: Identifiable, Equatable {
    let text: String
    let label: String
    var id: String { text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-") }

    init(_ text: String, label: String? = nil) {
        self.text = text
        self.label = label ?? text
    }
}
