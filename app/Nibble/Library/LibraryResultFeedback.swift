import SwiftUI

struct LibraryResultFeedback: ViewModifier {
    let library: LibraryModel
    let search: LibraryModel

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: library.feedback)
            .sensoryFeedback(.success, trigger: search.feedback)
    }
}
