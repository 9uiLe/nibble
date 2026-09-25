import AppMacros
import SwiftUI

@Equatable
struct VariableCompleteButton: View {
    private let inputRevision = UUID()
    let actionTitle: String
    let allValuesPresent: Bool
    let isSubmitting: Bool
    @SkipEquatable let complete: () -> Void

    var body: some View {
        Button(action: complete) {
            Text(isSubmitting ? "処理中…" : actionTitle)
        }
        .buttonStyle(NibbleActionButtonStyle(role: .primary))
        .disabled(!allValuesPresent || isSubmitting)
        .accessibilityHint(allValuesPresent ? "" : "すべての値を入力すると使えます")
        .accessibilityIdentifier("variables.complete")
    }
}
