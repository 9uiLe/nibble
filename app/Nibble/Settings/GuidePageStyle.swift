import SwiftUI

struct GuidePageStyle: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content.font(.nibbleBody).foregroundStyle(Color.nibblePrimary)
            .background(Color.nibbleCanvas).navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline).toolbarVisibility(.visible, for: .navigationBar)
    }
}
