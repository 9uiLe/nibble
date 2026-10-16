import SwiftUI

/// Component colors use the dynamic semantic palette defined by NibbleTheme.
struct IOSColorTokens: Sendable {
    let card: Color
    let cardForeground: Color
    let primary: Color
    let primaryForeground: Color
    let secondary: Color
    let secondaryForeground: Color
    let muted: Color
    let mutedForeground: Color
    let border: Color
    let destructive: Color
    let destructiveForeground: Color
    let destructiveText: Color
}

struct IOSSpacingTokens: Sendable {
    let xxs: CGFloat = 4
    let xs: CGFloat = 8
    let sm: CGFloat = 12
    let md: CGFloat = 16
    let lg: CGFloat = 24
}

struct IOSRadiusTokens: Sendable {
    let control: CGFloat = 12
    let card: CGFloat = 14
    let badge: CGFloat = 6
}

struct IOSTypographyTokens: Sendable {
    let button: Font = .nibbleTitle
    let badge: Font = .caption.weight(.semibold)
    let alertTitle: Font = .subheadline.weight(.semibold)
    let alertMessage: Font = .subheadline
}

struct IOSControlTokens: Sendable {
    let minimumHeight: CGFloat = 52
    let borderWidth: CGFloat = 1
    let emphasizedBorderWidth: CGFloat = 2
    let pressedOpacity: Double = 0.78
}

/// Layout and typography for the copied components; color values live in NibbleTheme.
struct IOSDesignTokens: Sendable {
    let colors: IOSColorTokens
    let spacing = IOSSpacingTokens()
    let radii = IOSRadiusTokens()
    let typography = IOSTypographyTokens()
    let controls = IOSControlTokens()
}

extension EnvironmentValues {
    @Entry var iosDesignTokens: IOSDesignTokens = .nibble
}
