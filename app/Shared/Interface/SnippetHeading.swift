import AppMacros
import SwiftUI

@Equatable
struct SnippetHeading: @MainActor EquatableBodyView {
    enum Style: Equatable { case library, keyboard }
    let title: String
    let pinned: Bool
    let style: Style
    var equatableBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if pinned && style == .library { Image(systemName: "pin.fill").font(.caption) }
            Text(verbatim: title).font(.nibbleTitle).lineLimit(style == .library ? 2 : 1)
            if pinned && style == .keyboard { Image(systemName: "pin.fill").font(.caption) }
        }
        .foregroundStyle(Color.nibblePrimary)
    }
}
