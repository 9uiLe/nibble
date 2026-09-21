import AppMacros
import SwiftUI

@Equatable
struct KeyboardFilterBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding

    var body: some View {
        ViewThatFits(in: .horizontal) {
            KeyboardFilterSegments(model: model, focus: focus).fixedSize(horizontal: true, vertical: false)
            KeyboardFilterSegments(model: model, focus: focus)
        }
    }
}
