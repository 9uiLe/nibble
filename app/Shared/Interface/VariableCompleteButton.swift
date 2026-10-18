import AppMacros
import SwiftUI

@MainActor @Equatable
struct VariableCompleteButton: View {
    private let inputRevision = UUID()
    let actionTitle: String
    let allValuesPresent: Bool
    let isSubmitting: Bool
    @SkipEquatable let complete: () -> Void
    var body: some View {
        Button(isSubmitting ? "処理中…" : actionTitle, action: complete)
            .buttonStyle(IOSButtonStyle(allValuesPresent ? .primary : .secondary))
            .disabled(isSubmitting || !allValuesPresent)
            .accessibilityHint(allValuesPresent ? "" : "すべての値を入力すると使えます")
            .accessibilityIdentifier("variables.complete")
    }
}
