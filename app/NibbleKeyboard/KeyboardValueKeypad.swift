import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardValueKeypad: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case kana = "かな", ascii = "英数", symbols = "記号", unicode = "文字コード"
        var id: Self { self }
    }
    private let inputRevision = UUID()
    @SkipEquatable let insert: (String) -> Void
    @State private var mode = Mode.kana
    @State private var page = 0
    private let pageSize = 15
    private var keys: [KeyboardValueKey] {
        switch mode {
        case .kana:
            Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽぁぃぅぇぉゃゅょっゎーゔゕゖ").map { KeyboardValueKey(String($0)) }
        case .ascii:
            Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map { KeyboardValueKey(String($0)) }
        case .symbols:
            [KeyboardValueKey(" ", label: "空白"), KeyboardValueKey("\n", label: "改行"), KeyboardValueKey("\t", label: "タブ")]
                + Array("。、！？「」『』（）・…〜、!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").reduce(into: [KeyboardValueKey]()) { result, character in
                    let text = String(character)
                    if !result.contains(where: { $0.text == text }) { result.append(KeyboardValueKey(text)) }
                }
                + [KeyboardValueKey("👩🏽‍💻"), KeyboardValueKey("😊"), KeyboardValueKey("❤️")]
        case .unicode: []
        }
    }
    private var pageCount: Int { max(1, (keys.count + pageSize - 1) / pageSize) }
    private var visibleKeys: [KeyboardValueKey] {
        Array(keys.dropFirst(min(page, pageCount - 1) * pageSize).prefix(pageSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Mode.allCases) { item in
                    Button {
                        mode = item
                        page = 0
                    } label: {
                        Text(verbatim: item.rawValue).font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                    }
                    .buttonStyle(.bordered).tint(mode == item ? Color.nibbleKeyboardAccent : Color.nibbleSecondary)
                    .accessibilityAddTraits(mode == item ? [.isSelected] : [])
                    .accessibilityIdentifier("variables.mode.\(item.rawValue)")
                }
            }
            switch mode {
            case .unicode:
                KeyboardUnicodeInput(insert: insert)
            case .kana:
                KeyboardKanaKeypad(insert: insert)
            case .ascii, .symbols:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 6) {
                    ForEach(visibleKeys) { key in
                        Button { insert(key.text) } label: {
                            Text(verbatim: key.label).font(.nibbleTitle)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("variables.key.\(key.id)")
                    }
                }
                HStack {
                    Button { page = max(0, page - 1) } label: {
                        Text("前の文字").font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                    }.disabled(page == 0).accessibilityIdentifier("variables.page.previous")
                    Text("\(page + 1) / \(pageCount)").font(.nibbleBody).fixedSize()
                        .accessibilityIdentifier("variables.page")
                    Button { page = min(pageCount - 1, page + 1) } label: {
                        Text("次の文字").font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                    }.disabled(page >= pageCount - 1).accessibilityIdentifier("variables.page.next")
                }.buttonStyle(.bordered)
            }
        }
    }
}
