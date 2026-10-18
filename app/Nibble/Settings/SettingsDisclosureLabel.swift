import AppMacros
import SwiftUI

@MainActor @Equatable
struct SettingsDisclosureLabel: View {
    private let inputRevision = UUID()
    let title: String
    let detail: String
    let systemImage: String
    var showsChevron = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).frame(width: 24).foregroundStyle(Color.nibbleSecondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.nibbleTitle)
                Text(detail).font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { Image(systemName: "chevron.right").foregroundStyle(Color.nibbleSecondary) }
        }.padding(.vertical, 8).frame(minHeight: 44)
    }
}
