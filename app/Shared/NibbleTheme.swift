import SwiftUI

extension Color {
    static let nibbleSelection = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.88, green: 0.90, blue: 0.84, alpha: 1)
            : UIColor(red: 0.20, green: 0.23, blue: 0.20, alpha: 1)
    })
    static let nibbleOnSelection = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.19, blue: 0.14, alpha: 1)
            : UIColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 1)
    })
    static let nibbleSoft = Color.nibbleAccent.opacity(0.09)
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
