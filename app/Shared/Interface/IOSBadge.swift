import AppMacros
import SwiftUI

@MainActor @Equatable
struct IOSBadge: View {
    private let inputRevision = UUID()
    let title: String
    let symbol: String?
    init(_ title: String, symbol: String? = nil) { self.title = title; self.symbol = symbol }
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(Color.nibbleOnAccent)
        .background(Color.nibbleAccent, in: .rect(cornerRadius: 6))
    }
}
