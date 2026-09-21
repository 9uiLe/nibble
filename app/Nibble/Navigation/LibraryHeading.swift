import AppMacros
import SwiftUI

@Equatable
struct LibraryHeading: View {
    private let inputRevision = UUID()
    let title: String
    var subTitle: String? = nil
    @SkipEquatable let model: LibraryModel
    var showsCreation = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenHeading(title: title, subTitle: subTitle)
            if showsCreation { CreateSnippetButton(model: model) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}
