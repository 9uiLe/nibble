import SwiftUI

/// The content window supplies a bottom edge that already accounts for the creation action and keyboard.
struct LibraryNoticeOverlay: ViewModifier {
    let model: LibraryModel
    let taskOwner: LibraryTaskOwner
    let isPresented: Bool

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                LibraryNoticeWindow(model: model, taskOwner: taskOwner, isPresented: isPresented,
                                    bottomBoundary: geometry.frame(in: .global).maxY - InterfaceMetrics.noticeSpacing)
            }
        }
    }
}
