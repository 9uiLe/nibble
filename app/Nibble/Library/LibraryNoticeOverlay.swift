import SwiftUI

struct LibraryNoticeOverlay: ViewModifier {
    let model: LibraryModel
    let taskOwner: LibraryTaskOwner
    let isPresented: Bool
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { layout in
                LibraryNoticeWindow(model: model, taskOwner: taskOwner, isPresented: isPresented,
                                    bottomBoundary: layout.frame(in: .global).maxY - 8)
            }
        }
    }
}
