import AppMacros
import SwiftUI

@Equatable
struct KeyboardDetailHeader: View {
    private let inputRevision = UUID()
    let detail: KeyboardModel.Detail
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Button("一覧に戻る", systemImage: "chevron.left", action: model.closeDetail)
                .accessibilityIdentifier("keyboard.back")
                .accessibilityFocused(focus, equals: "back")
            Spacer(minLength: 0)
            Button { taskOwner.startTask(on: model) } label: {
                Image(systemName: detail.item.pinned ? "pin.fill" : "pin")
            }
            .accessibilityLabel(detail.item.pinned ? "ピン留めを解除" : "ピン留め")
            .accessibilityValue(detail.item.pinned ? "ピン留め済み" : "")
            .accessibilityHint(model.hasFullAccess ? "" : "フルアクセスの案内を表示します")
            .accessibilityIdentifier("keyboard.pin")
            .disabled(model.isUsing || detail.body == nil)
        }
        .font(.subheadline).buttonStyle(KeyboardControlStyle())
        .padding(.horizontal, 10)
    }
}
