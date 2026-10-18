import AppMacros
import SwiftUI

enum IOSAlertVariant: Equatable { case information, error }
@MainActor @Equatable
struct IOSInlineAlert: View {
    private let inputRevision = UUID()
    let title: String
    let message: String
    let variant: IOSAlertVariant
    init(_ title: String, message: String, variant: IOSAlertVariant = .information) {
        self.title = title; self.message = message; self.variant = variant
    }
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.nibbleTitle)
                Text(message).font(.nibbleBody).fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: variant == .error ? "exclamationmark.triangle" : "info.circle")
        }
        .foregroundStyle(variant == .error ? Color.nibbleErrorText : .nibblePrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.nibbleSoft, in: .rect(cornerRadius: 12))
    }
}
