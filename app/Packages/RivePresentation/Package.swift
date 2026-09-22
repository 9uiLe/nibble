// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RivePresentation",
    platforms: [.iOS("26.0")],
    products: [.library(name: "RivePresentation", targets: ["RivePresentation"])],
    dependencies: [
        .package(path: "../../../artifacts/RiveRuntime"),
        .package(url: "https://github.com/9uiLe/swift-app-macros.git", exact: "0.3.0")
    ],
    targets: [.target(name: "RivePresentation", dependencies: [
        .product(name: "RiveRuntime", package: "RiveRuntime"),
        .product(name: "AppMacros", package: "swift-app-macros")
    ])]
)
