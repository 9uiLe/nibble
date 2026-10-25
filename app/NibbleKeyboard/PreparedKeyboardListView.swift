import AppMacros
import SwiftUI

@Equatable
struct PreparedKeyboardListView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: PreparedKeyboardModel
    @SkipEquatable let owner: PreparedKeyboardTaskOwner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("最大50件の固定文を表示します。変数の差し替えや、ここにない文章の検索はnibble本体で行い、完成文をコピーしてペーストしてください。")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("keyboard.scopeGuide")
                switch model.listing {
                case .idle:
                    Text("保存済みの文章を読み込みます。")
                case .loading:
                    ProgressView("読込中")
                case .failed(let error):
                    Text(PreparedKeyboardMessage.readFailure(error))
                        .accessibilityIdentifier("keyboard.readError")
                case .cards(let cards):
                    if cards.isEmpty {
                        Text("本体で固定文をピン留めすると、ここで全文を確認して挿入できます。")
                            .accessibilityIdentifier("keyboard.empty")
                    }
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(cards) { card in
                            Button { owner.startTask(.select(card)) } label: {
                                PreparedKeyboardRow(summary: card)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("keyboard.card.\(card.id.uuidString)")
                            .accessibilityHint("全文を確認します。まだ挿入しません。")
                        }
                    }
                }
                Button("再読み込み") { owner.startTask(.reload) }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("keyboard.reload")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("keyboard.list")
    }
}
