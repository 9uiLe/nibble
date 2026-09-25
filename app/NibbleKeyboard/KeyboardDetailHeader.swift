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
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("keyboard.back")
                .accessibilityFocused(focus, equals: "back")
            Text(detail.item.displayTitle).font(.subheadline.weight(.semibold))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button {
                taskOwner.startTask(on: model)
            } label: {
                Label(detail.item.pinned ? "ピン解除" : "ピン留め",
                    systemImage: detail.item.pinned ? "pin.fill" : "pin")
            }
                .accessibilityLabel(detail.item.pinned ? "ピン留めを解除" : "ピン留め")
                .accessibilityValue(detail.item.pinned ? "ピン留め済み" : "ピン留めなし")
                .accessibilityHint(model.hasFullAccess ? "" : "フルアクセスの案内を表示します")
                .accessibilityIdentifier("keyboard.pin")
                .disabled(model.isUsing || detail.body == nil)
        }
        .font(.subheadline).buttonStyle(KeyboardControlStyle())
        .padding(.horizontal, 10)
    }
}
