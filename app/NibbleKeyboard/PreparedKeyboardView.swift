import AppMacros
import SwiftUI
import UIKit

@Equatable
struct PreparedKeyboardView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: PreparedKeyboardModel
    @SkipEquatable let owner: PreparedKeyboardTaskOwner
    @SkipEquatable let globe: UIButton

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("ピン留めした固定文").font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                if model.needsInputModeSwitchKey {
                    PreparedKeyboardInputModeButton(button: globe).frame(width: 44, height: 44)
                }
                Button("閉じる") { model.dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("keyboard.dismiss")
            }
            switch model.preview {
            case .some(let preview):
                PreparedKeyboardPreviewView(model: model, owner: owner, preview: preview)
            case .none:
                PreparedKeyboardListView(model: model, owner: owner)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onDisappear { owner.cancelAll() }
    }
}
