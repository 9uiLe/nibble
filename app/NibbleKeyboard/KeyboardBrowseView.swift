import AppMacros
import SwiftUI

@Equatable
struct KeyboardBrowseView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    @Binding var detailOrigin: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                KeyboardFilterBar(model: model, focus: focus)
                Spacer(minLength: 0)
                Button("更新", systemImage: "arrow.clockwise", action: model.requestReload)
                    .labelStyle(.iconOnly)
                    .buttonStyle(KeyboardControlStyle())
                    .accessibilityIdentifier("keyboard.refresh")
            }
            .padding(.horizontal, 10)
            KeyboardListContent(model: model, taskOwner: taskOwner, focus: focus, detailOrigin: $detailOrigin)
                .modifier(KeyboardPanelStyle())
        }
    }
}
