// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RivePresentation",
    platforms: [.iOS("26.0")],
    products: [.library(name: "RivePresentation", targets: ["RivePresentation"])],
    dependencies: [
        .package(url: "https://github.com/rive-app/rive-ios", exact: "6.27.0"),
        .package(url: "https://github.com/9uiLe/swift-app-macros.git", exact: "0.3.0")
    ],
    targets: [.target(name: "RivePresentation", dependencies: [
        .product(name: "RiveRuntime", package: "rive-ios"),
        .product(name: "AppMacros", package: "swift-app-macros")
    ])]
)
