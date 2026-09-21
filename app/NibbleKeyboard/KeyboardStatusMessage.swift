import AppMacros
import SwiftUI

@Equatable
struct KeyboardStatusMessage: @MainActor EquatableBodyView {
    let notice: KeyboardModel.Notice?

    var equatableBody: some View {
        if let notice = notice, !notice.expires {
            ScrollView {
                Text(notice.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 72)
        } else {
            Text(notice?.message ?? "nibble").lineLimit(2)
        }
    }
}
