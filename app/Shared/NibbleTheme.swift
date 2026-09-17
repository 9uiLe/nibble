import SwiftUI

extension Color {
    static let nibbleAccent = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        return dark ? UIColor(red: 1, green: 0.64, blue: 0.39, alpha: 1)
                    : UIColor(red: 0.64, green: 0.24, blue: 0.08, alpha: 1)
    })
    static let nibbleCanvas = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        return dark ? UIColor(red: 0.08, green: 0.085, blue: 0.08, alpha: 1)
                    : UIColor(red: 0.975, green: 0.968, blue: 0.95, alpha: 1)
    })
}
