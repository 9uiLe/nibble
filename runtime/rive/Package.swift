// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiveRuntime",
    platforms: [.iOS("26.0")],
    products: [.library(name: "RiveRuntime", targets: ["RiveRuntime"])],
    targets: [.binaryTarget(name: "RiveRuntime", path: "RiveRuntime.xcframework")]
)
