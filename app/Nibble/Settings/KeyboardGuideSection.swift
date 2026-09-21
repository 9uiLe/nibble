import AppMacros
import SwiftUI

@Equatable
struct KeyboardGuideSection: @MainActor EquatableBodyView {
    let title: String
    let text: String

    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.nibbleTitle).accessibilityAddTraits(.isHeader)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
