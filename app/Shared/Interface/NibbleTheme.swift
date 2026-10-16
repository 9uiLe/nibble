import SwiftUI

extension Font {
    static let nibbleScreenTitle = Font.system(size: 26, weight: .bold)
    static let nibbleTitle = Font.body.weight(.semibold)
    static let nibbleBody = Font.subheadline
}

extension Color {
    // Opaque, role-based pairs keep the reading hierarchy stable on every surface.
    static let nibbleCanvas = nibbleColor(light: 0xFFFFFF, dark: 0x111111)
    static let nibbleSurface = nibbleColor(light: 0xF2F2F2, dark: 0x242424)
    static let nibblePrimary = nibbleColor(light: 0x181818, dark: 0xF6F6F6)
    static let nibbleSecondary = nibbleColor(light: 0x555555, dark: 0xBDBDBD)
    static let nibbleSeparator = nibbleColor(light: 0xD1D1D1, dark: 0x484848)
    static let nibbleBorder = nibbleColor(light: 0x767676, dark: 0x929292)
    static let nibbleAccent = nibblePrimary
    static let nibbleOnAccent = nibbleColor(light: 0xFFFFFF, dark: 0x181818)
    static let nibbleSoft = nibbleColor(light: 0xEAEAEA, dark: 0x303030)
    static let nibbleSelection = nibbleColor(light: 0x242424, dark: 0xEAEAEA)
    static let nibbleOnSelection = nibbleColor(light: 0xFFFFFF, dark: 0x181818)
    static let nibbleDestructive = nibbleColor(light: 0x942727, dark: 0x8C3030)
    static let nibbleErrorText = nibbleColor(light: 0x8C2020, dark: 0xFFC5C5)

    private static func nibbleColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }
}

extension IOSDesignTokens {
    // NibbleTheme owns the color values; copied Evoloom components use this adapter.
    static let nibble: IOSDesignTokens = {
        let colors = IOSColorTokens(
            background: .nibbleCanvas, foreground: .nibblePrimary,
            card: .nibbleSurface, cardForeground: .nibblePrimary,
            primary: .nibbleAccent, primaryForeground: .nibbleOnAccent,
            secondary: .nibbleSurface, secondaryForeground: .nibblePrimary,
            muted: .nibbleSoft, mutedForeground: .nibbleSecondary,
            border: .nibbleBorder, input: .nibbleBorder,
            destructive: .nibbleDestructive, destructiveForeground: .white,
            destructiveText: .nibbleErrorText, success: .nibbleSelection,
            successForeground: .nibbleOnSelection,
            toggleOnBackground: .nibbleAccent,
            cardMutedForeground: .nibbleSecondary
        )
        var tokens = IOSDesignTokens(light: colors, dark: colors)
        tokens.controls.minimumHeight = 52
        tokens.controls.pressedOpacity = 0.78
        tokens.radii.control = 12
        tokens.typography.button = .nibbleTitle
        return tokens
    }()
}
