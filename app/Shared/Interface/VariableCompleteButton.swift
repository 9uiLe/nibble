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
                .font(.nibbleTitle)
                .foregroundStyle(allValuesPresent ? Color.nibbleCanvas : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(allValuesPresent ? Color.nibbleAccent : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if !allValuesPresent {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!allValuesPresent || isSubmitting)
        .accessibilityHint(allValuesPresent ? "" : "すべての値を入力すると使えます")
        .accessibilityIdentifier("variables.complete")
    }
}
