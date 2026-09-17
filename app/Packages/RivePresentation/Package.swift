// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RivePresentation",
    platforms: [.iOS("26.0")],
    products: [.library(name: "RivePresentation", targets: ["RivePresentation"])],
    dependencies: [.package(url: "https://github.com/rive-app/rive-ios", exact: "6.27.0")],
    targets: [.target(name: "RivePresentation", dependencies: [
        .product(name: "RiveRuntime", package: "rive-ios")
    ])]
)
