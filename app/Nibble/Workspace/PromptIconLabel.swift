import AppMacros
import SwiftUI

@Equatable
struct PromptIconLabel: @MainActor EquatableBodyView {
    let title: String
    let symbol: String

    var equatableBody: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.system(size: 20))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
