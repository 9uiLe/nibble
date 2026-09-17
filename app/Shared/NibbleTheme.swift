import SwiftUI

extension Color {
    static let nibbleAccent = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        if traits.accessibilityContrast == .high {
            return dark ? UIColor(red: 1, green: 0.78, blue: 0.56, alpha: 1)
                        : UIColor(red: 0.44, green: 0.13, blue: 0.02, alpha: 1)
        }
        return dark ? UIColor(red: 1, green: 0.64, blue: 0.39, alpha: 1)
                    : UIColor(red: 0.64, green: 0.24, blue: 0.08, alpha: 1)
    })
    static let nibbleCanvas = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        if traits.accessibilityContrast == .high {
            return dark ? UIColor(red: 0.02, green: 0.025, blue: 0.02, alpha: 1) : .white
        }
        return dark ? UIColor(red: 0.08, green: 0.085, blue: 0.08, alpha: 1)
                    : UIColor(red: 0.975, green: 0.968, blue: 0.95, alpha: 1)
    })
}
