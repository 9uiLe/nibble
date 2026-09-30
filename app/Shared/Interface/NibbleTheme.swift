import SwiftUI

extension Font {
    static let nibbleScreenTitle = Font.system(size: 26, weight: .bold)
    static let nibbleTitle = Font.body.weight(.semibold)
    static let nibbleBody = Font.subheadline
}

extension Color {
    // Opaque, role-based pairs keep the reading hierarchy stable on every surface.
    static let nibbleCanvas = nibbleColor(light: 0xFAF8F4, dark: 0x171614)
    static let nibbleSurface = nibbleColor(light: 0xEEE9E1, dark: 0x272420)
    static let nibblePrimary = nibbleColor(light: 0x292622, dark: 0xF2EDE6)
    static let nibbleSecondary = nibbleColor(light: 0x6C655C, dark: 0xBDB5AA)
    static let nibbleSeparator = nibbleColor(light: 0xDFD8CE, dark: 0x403A32)
    static let nibbleBorder = nibbleColor(light: 0x8D8478, dark: 0x877C6D)
    static let nibbleAccent = nibbleColor(light: 0x9B481F, dark: 0xF3AD7E)
    static let nibbleOnAccent = nibbleColor(light: 0xFFF8F2, dark: 0x251B14)
    static let nibbleSoft = nibbleColor(light: 0xF4E6DA, dark: 0x34271F)
    static let nibbleSelection = nibbleColor(light: 0x363029, dark: 0xE8DED0)
    static let nibbleOnSelection = nibbleColor(light: 0xFAF8F4, dark: 0x211D18)

    private static func nibbleColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }
}

struct NibbleActionButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
    }

    @Environment(\.isEnabled) private var isEnabled
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        let primary = role == .primary
        let radius: CGFloat = 12
        configuration.label
            .font(.nibbleTitle)
            .foregroundStyle(primary && isEnabled ? Color.nibbleOnAccent : Color.nibblePrimary)
            .padding(.horizontal, primary ? 16 : 12)
            .frame(maxWidth: .infinity, minHeight: primary ? 52 : 48)
            .background(primary && isEnabled ? Color.nibbleAccent : Color.nibbleSurface,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.nibbleBorder.opacity(primary && isEnabled ? 0 : 1))
            }
            .opacity(configuration.isPressed && isEnabled ? 0.78 : 1)
            .contentShape(.rect)
    }
}
