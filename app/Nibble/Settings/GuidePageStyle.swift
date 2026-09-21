import SwiftUI

struct GuidePageStyle: ViewModifier {
    let title: LocalizedStringKey

    func body(content: Content) -> some View {
        content
            .modifier(TabBarScrollTracking())
            .background(Color.nibbleCanvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
