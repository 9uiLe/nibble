import SwiftUI
import UIKit

@MainActor
enum WorkspaceStyle {
    static let text = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .label : UIColor(white: 32 / 255, alpha: 1)
    })
    static let secondary = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high { return .secondaryLabel }
        return traits.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(white: 100 / 255, alpha: 1)
    })
    static let subtle = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : UIColor(white: 240 / 255, alpha: 1)
    })
    static let divider = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high { return .separator }
        return traits.userInterfaceStyle == .dark ? .separator : UIColor(white: 224 / 255, alpha: 1)
    })
}
