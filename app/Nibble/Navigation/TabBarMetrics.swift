import CoreGraphics

/// The reserved area is constant, so animation cannot feed back into scroll geometry.
enum TabBarMetrics {
    static let iconSize: CGFloat = 24
    static let compactIconSize: CGFloat = 16
    static let compactScale: CGFloat = 0.85
    static let buttonHeight: CGFloat = 52
    static let bottomSpacing: CGFloat = 8
    static let reservedHeight: CGFloat = 76
    static let compactIconScale = compactIconSize / (iconSize * compactScale)
}
