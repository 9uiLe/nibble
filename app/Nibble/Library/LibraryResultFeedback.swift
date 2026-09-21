import SwiftUI

struct LibraryResultFeedback: ViewModifier {
    let all: LibraryModel
    let search: LibraryModel

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: all.feedback)
            .sensoryFeedback(.success, trigger: search.feedback)
    }
}
