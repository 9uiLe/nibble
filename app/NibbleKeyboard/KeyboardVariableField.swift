import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardVariableField: View {
    private let inputRevision = UUID()
    let name: VariableName
    let value: String
    let selected: Bool
    @SkipEquatable let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(name.marker) に入れる値").font(.nibbleTitle)
                Text(verbatim: value.isEmpty ? "値を入力" : value).font(.nibbleBody).lineLimit(2)
                    .foregroundStyle(value.isEmpty ? Color.nibbleSecondary : Color.nibblePrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(8).contentShape(.rect)
        }
        .buttonStyle(.bordered).tint(selected ? Color.nibbleKeyboardAccent : Color.nibbleSecondary)
        .accessibilityLabel("\(name.marker) に入れる値")
        .accessibilityValue(value.isEmpty ? "未入力" : value)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("variables.field.\(name.text)")
    }
}
