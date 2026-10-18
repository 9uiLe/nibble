import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardKanaKeypad: View {
    private struct Row: Identifiable, Equatable {
        let title: String
        let characters: String
        var id: String { title }
    }
    private let inputRevision = UUID()
    @SkipEquatable let insert: (String) -> Void
    @State private var selected: Row?
    private let rows = [
        Row(title: "あ", characters: "あいうえお"), Row(title: "か", characters: "かきくけこ"), Row(title: "さ", characters: "さしすせそ"),
        Row(title: "た", characters: "たちつてと"), Row(title: "な", characters: "なにぬねの"), Row(title: "は", characters: "はひふへほ"),
        Row(title: "ま", characters: "まみむめも"), Row(title: "や", characters: "やゆよ"), Row(title: "ら", characters: "らりるれろ"),
        Row(title: "わ", characters: "わをんー"), Row(title: "濁音", characters: "がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ"),
        Row(title: "小書き", characters: "ぁぃぅぇぉゃゅょっゎゔゕゖ")
    ]

    var body: some View {
        VStack(spacing: 6) {
            switch selected {
            case .some(let row):
                Button { selected = nil } label: {
                    Label("かなの行へ", systemImage: "chevron.backward").font(.nibbleTitle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.buttonStyle(.bordered).accessibilityIdentifier("variables.kana.rows")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 6) {
                    ForEach(Array(row.characters).map { KeyboardValueKey(String($0)) }) { key in
                        Button { insert(key.text) } label: {
                            Text(verbatim: key.label).font(.nibbleTitle)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.bordered).accessibilityIdentifier("variables.key.\(key.id)")
                    }
                }
            case .none:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 6) {
                    ForEach(rows) { row in
                        Button { selected = row } label: {
                            Text(verbatim: row.title).font(.nibbleTitle)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.bordered).accessibilityIdentifier("variables.kana.row.\(row.title)")
                    }
                }
            }
        }
    }
}
