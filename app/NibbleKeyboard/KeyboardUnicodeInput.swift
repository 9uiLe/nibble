import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardUnicodeInput: View {
    private let inputRevision = UUID()
    @SkipEquatable let insert: (String) -> Void
    @State private var digits = ""
    private let hexadecimal = Array("0123456789ABCDEF").map(String.init)
    private var scalar: Unicode.Scalar? {
        guard !digits.isEmpty, let number = UInt32(digits, radix: 16) else { return nil }
        return Unicode.Scalar(number)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unicodeの文字コードを16進数で入力します。例: 1F600 は 😀、0301 は結合文字です。複数の文字は一つずつ追加できます。")
                .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
            Text(verbatim: "U+" + (digits.isEmpty ? "…" : digits)).font(.nibbleTitle)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("variables.unicode.code")
            if let scalar {
                Text(verbatim: "追加する文字: " + String(scalar)).font(.nibbleBody)
                    .accessibilityIdentifier("variables.unicode.preview")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 6) {
                ForEach(hexadecimal, id: \.self) { digit in
                    Button {
                        guard digits.count < 6 else { return }
                        digits += digit
                    } label: {
                        Text(verbatim: digit).font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                    }.buttonStyle(.bordered).accessibilityIdentifier("variables.unicode.digit.\(digit)")
                }
            }
            HStack(spacing: 6) {
                Button {
                    if !digits.isEmpty { digits.removeLast() }
                } label: {
                    Text("1桁削除").font(.nibbleTitle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.disabled(digits.isEmpty).accessibilityIdentifier("variables.unicode.delete")
                Button { digits = "" } label: {
                    Text("コードを消去").font(.nibbleTitle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.disabled(digits.isEmpty).accessibilityIdentifier("variables.unicode.clear")
            }.buttonStyle(.bordered)
            Button {
                guard let scalar else { return }
                insert(String(scalar))
                digits = ""
            } label: {
                Text("この文字を追加").font(.nibbleTitle)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.borderedProminent).disabled(scalar == nil)
            .accessibilityIdentifier("variables.unicode.insert")
            if scalar == nil && !digits.isEmpty {
                Text("有効な文字コードを入力してください。0000〜10FFFFのうち、D800〜DFFFは文字として追加できません。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                    .accessibilityIdentifier("variables.unicode.invalid")
            }
        }
    }
}
