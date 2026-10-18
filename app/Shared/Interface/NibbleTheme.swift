import SwiftUI

extension Font {
    static let nibbleScreenTitle: Font = .system(size: 26, weight: .bold)
    static let nibbleTitle: Font = .system(size: 17, weight: .semibold)
    static let nibbleBody: Font = .system(size: 15)
}

extension Color {
    private static func palette(_ day: UInt32, _ night: UInt32) -> Color {
        Color(uiColor: UIColor { appearance in
            let value = appearance.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat(value >> 16 & 255) / 255,
                           green: CGFloat(value >> 8 & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let nibbleCanvas = palette(0xffffff, 0x111111)
    static let nibbleSurface = palette(0xf2f2f2, 0x242424)
    static let nibblePrimary = palette(0x181818, 0xf6f6f6)
    static let nibbleSecondary = palette(0x555555, 0xbdbdbd)
    static let nibbleBorder = palette(0x767676, 0x929292)
    static let nibbleSeparator = palette(0xd1d1d1, 0x484848)
    static let nibbleSoft = palette(0xeaeaea, 0x303030)
    static let nibbleSelection = palette(0x242424, 0xeaeaea)
    static let nibbleOnSelection = palette(0xffffff, 0x181818)
    static let nibbleKeyboardAccent = palette(0x0057b8, 0x90c2ff)
    static let nibbleKeyboardFill = palette(0x004fa5, 0x90c2ff)
    static let nibbleKeyboardOnFill = palette(0xffffff, 0x181818)
    static let nibbleKeyboardHighlight = palette(0xdfebfb, 0x243e5d)
    static let nibbleAccent = nibblePrimary
    static let nibbleOnAccent = palette(0xffffff, 0x181818)
    static let nibbleDestructive = palette(0x942727, 0x8c3030)
    static let nibbleErrorText = palette(0x8c2020, 0xffc5c5)
}

extension IOSDesignTokens {
    static let nibble = IOSDesignTokens(colors: .init(
        card: .nibbleSurface, cardForeground: .nibblePrimary,
        primary: .nibbleAccent, primaryForeground: .nibbleOnAccent,
        secondary: .nibbleSurface, secondaryForeground: .nibblePrimary,
        muted: .nibbleSoft, mutedForeground: .nibbleSecondary,
        border: .nibbleBorder, destructive: .nibbleDestructive,
        destructiveForeground: .white, destructiveText: .nibbleErrorText))
}

extension IOSDesignTokens {
    static let nibbleKeyboard = IOSDesignTokens(colors: .init(
        card: .nibbleSurface, cardForeground: .nibblePrimary,
        primary: .nibbleKeyboardFill, primaryForeground: .nibbleKeyboardOnFill,
        secondary: .nibbleSurface, secondaryForeground: .nibblePrimary,
        muted: .nibbleSoft, mutedForeground: .nibbleSecondary,
        border: .nibbleBorder, destructive: .nibbleDestructive,
        destructiveForeground: .white, destructiveText: .nibbleErrorText))
}
