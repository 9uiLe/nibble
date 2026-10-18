import AppMacros
import SwiftUI

@Equatable
struct KeyboardGuideSection: @MainActor EquatableBodyView {
    let title: String
    let text: String
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.nibbleTitle).accessibilityAddTraits(.isHeader)
            Text(text).font(.nibbleBody).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
