import AppMacros
import SwiftUI

@Equatable
struct KeyboardDetailActions: View {
    private let inputRevision = UUID()
    let detail: KeyboardModel.Detail
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner

    var body: some View {
        HStack(spacing: 10) {
            Button { taskOwner.startTask(detail.item, as: .copy, on: model) } label: {
                Label("コピー", systemImage: model.hasFullAccess ? "doc.on.doc" : "lock.doc")
                    .frame(minHeight: 44).padding(.horizontal, 12)
                    .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 10))
            }
            .accessibilityIdentifier("keyboard.copy.\(detail.item.id)")
            .accessibilityHint(model.hasFullAccess ? "本文をコピーします" : "フルアクセスの設定方法を表示します")
            Button { taskOwner.startTask(detail.item, as: .insert, on: model) } label: {
                Text("入力する").fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white)
                    .background(Color(uiColor: .systemBlue), in: .rect(cornerRadius: 10))
            }
            .accessibilityIdentifier("keyboard.detail.insert")
        }
        .font(.subheadline).buttonStyle(.plain)
        .disabled(model.isUsing || detail.body == nil || !model.isCurrent)
        .padding(.horizontal, 10).padding(.top, 6)
    }
}
