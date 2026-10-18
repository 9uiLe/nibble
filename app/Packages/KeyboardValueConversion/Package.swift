// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KeyboardValueConversion",
    platforms: [.iOS("26.0")],
    products: [.library(name: "KeyboardValueConversion", targets: ["KeyboardValueConversion"])],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2", traits: []),
    ],
    targets: [
        .target(
            name: "KeyboardValueConversion",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
            ]
        ),
        .testTarget(name: "KeyboardValueConversionTests", dependencies: ["KeyboardValueConversion"]),
    ],
    swiftLanguageModes: [.v6]
)
