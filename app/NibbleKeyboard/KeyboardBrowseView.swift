import AppMacros
import SwiftUI

@Equatable
struct KeyboardBrowseView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    @Binding var detailOrigin: UUID?
    @Binding var listPosition: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                KeyboardFilterBar(model: model, focus: focus)
                Spacer(minLength: 0)
                if model.loadFailure != nil || model.notice?.expires == false {
                    Button("再読み込み", systemImage: "arrow.clockwise", action: model.requestReload)
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(KeyboardControlStyle())
                        .accessibilityHint("選択中の一覧を先頭から読み直します")
                        .accessibilityIdentifier("keyboard.refresh")
                }
            }
            .padding(.horizontal, 10)
            KeyboardListContent(model: model, taskOwner: taskOwner, focus: focus,
                detailOrigin: $detailOrigin, listPosition: $listPosition)
                .modifier(KeyboardPanelStyle())
        }
    }
}
