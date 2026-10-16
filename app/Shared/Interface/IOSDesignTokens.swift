import SwiftUI

/// Semantic colors are paired so callers do not need to invent contrast relationships.
public struct IOSColorTokens: Sendable {
    public var background: Color
    public var foreground: Color
    public var card: Color
    public var cardForeground: Color
    public var cardMutedForeground: Color
    public var primary: Color
    public var primaryForeground: Color
    public var secondary: Color
    public var secondaryForeground: Color
    public var muted: Color
    public var mutedForeground: Color
    public var border: Color
    public var input: Color
    /// The native Toggle track color while its value is on.
    public var toggleOnBackground: Color
    public var destructive: Color
    public var destructiveForeground: Color
    public var destructiveText: Color
    public var success: Color
    public var successForeground: Color

    public init(
        background: Color, foreground: Color, card: Color, cardForeground: Color,
        primary: Color, primaryForeground: Color, secondary: Color,
        secondaryForeground: Color, muted: Color, mutedForeground: Color,
        border: Color, input: Color, destructive: Color, destructiveForeground: Color,
        destructiveText: Color, success: Color, successForeground: Color,
        toggleOnBackground: Color? = nil, cardMutedForeground: Color? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.card = card
        self.cardForeground = cardForeground
        self.cardMutedForeground = cardMutedForeground ?? cardForeground
        self.primary = primary
        self.primaryForeground = primaryForeground
        self.secondary = secondary
        self.secondaryForeground = secondaryForeground
        self.muted = muted
        self.mutedForeground = mutedForeground
        self.border = border
        self.input = input
        self.toggleOnBackground = toggleOnBackground ?? primary
        self.destructive = destructive
        self.destructiveForeground = destructiveForeground
        self.destructiveText = destructiveText
        self.success = success
        self.successForeground = successForeground
    }
}

public struct IOSSpacingTokens: Sendable {
    public var xxs: CGFloat = 4
    public var xs: CGFloat = 8
    public var sm: CGFloat = 12
    public var md: CGFloat = 16
    public var lg: CGFloat = 24
    public var xl: CGFloat = 32

    public init() {}
}

public struct IOSRadiusTokens: Sendable {
    public var control: CGFloat = 10
    public var card: CGFloat = 14
    public var badge: CGFloat = 6

    public init() {}
}

/// System text styles retain Dynamic Type behavior when applied to a view.
public struct IOSTypographyTokens: Sendable {
    public var button: Font = .body.weight(.semibold)
    public var fieldLabel: Font = .subheadline.weight(.medium)
    public var supporting: Font = .footnote
    public var badge: Font = .caption.weight(.semibold)
    public var cardTitle: Font = .headline
    public var cardDetail: Font = .subheadline
    public var alertTitle: Font = .subheadline.weight(.semibold)
    public var alertMessage: Font = .subheadline
    public var emptyTitle: Font = .headline
    public var emptyMessage: Font = .subheadline
    public var emptyIcon: Font = .largeTitle

    public init() {}
}

/// Repeated component dimensions. Callers can scale the text area height with Dynamic Type.
public struct IOSControlTokens: Sendable {
    public static let defaultTextAreaHeight: CGFloat = 110

    public var minimumHeight: CGFloat = 44
    public var textAreaHeight: CGFloat = Self.defaultTextAreaHeight
    public var skeletonHeight: CGFloat = 20
    public var separatorThickness: CGFloat = 1
    public var borderWidth: CGFloat = 1
    public var emphasizedBorderWidth: CGFloat = 2
    public var pressedOpacity: Double = 0.75

    public init() {}
}

/// The complete set of visual decisions shared by the components.
public struct IOSDesignTokens: Sendable {
    public var light: IOSColorTokens
    public var dark: IOSColorTokens
    public var spacing: IOSSpacingTokens
    public var radii: IOSRadiusTokens
    public var typography: IOSTypographyTokens
    public var controls: IOSControlTokens

    public init(
        light: IOSColorTokens, dark: IOSColorTokens,
        spacing: IOSSpacingTokens = .init(), radii: IOSRadiusTokens = .init(),
        typography: IOSTypographyTokens = .init(), controls: IOSControlTokens = .init()
    ) {
        self.light = light
        self.dark = dark
        self.spacing = spacing
        self.radii = radii
        self.typography = typography
        self.controls = controls
    }

    // Source-owned adaptation: the product theme is the only palette authority.
    public static var neutral: IOSDesignTokens { .nibble }
}

public extension EnvironmentValues {
    @Entry var iosDesignTokens: IOSDesignTokens = .nibble

    var iosTheme: IOSTheme {
        get { iosDesignTokens }
        set { iosDesignTokens = newValue }
    }
}

public typealias IOSPalette = IOSColorTokens
public typealias IOSSpacing = IOSSpacingTokens
public typealias IOSRadii = IOSRadiusTokens
public typealias IOSTheme = IOSDesignTokens

extension IOSDesignTokens {
    func palette(for scheme: ColorScheme) -> IOSColorTokens {
        scheme == .dark ? dark : light
    }
}
