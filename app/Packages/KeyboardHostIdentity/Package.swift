// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardHostIdentity",
    platforms: [.iOS("26.0")],
    products: [.library(name: "KeyboardHostIdentity", targets: ["KeyboardHostIdentity"])],
    targets: [
        .target(name: "KeyboardHostIdentity"),
        .target(
            name: "KeyboardHostIdentityFixtures",
            path: "Tests/Fixtures",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "KeyboardHostIdentityTests",
            dependencies: ["KeyboardHostIdentity", "KeyboardHostIdentityFixtures"],
            path: "Tests/KeyboardHostIdentityTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
