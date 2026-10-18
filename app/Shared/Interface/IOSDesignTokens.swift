import SwiftUI

struct IOSColorTokens: Sendable {
    let card, cardForeground, primary, primaryForeground: Color
    let secondary, secondaryForeground, muted, mutedForeground: Color
    let border, destructive, destructiveForeground, destructiveText: Color
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
    let alertTitle: Font = .nibbleTitle
    let alertMessage: Font = .nibbleBody
}
struct IOSControlTokens: Sendable {
    let minimumHeight: CGFloat = 52
    let borderWidth: CGFloat = 1
    let emphasizedBorderWidth: CGFloat = 2
    let pressedOpacity: Double = 0.78
}
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
