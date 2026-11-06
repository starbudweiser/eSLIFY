// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "eSLIFY",
    platforms: [.macOS(.v15)],
    targets: [
        // Tables, calcul des codes et traductions, sans interface (testable seul)
        .target(name: "EslCore"),
        .executableTarget(name: "eSLIFY", dependencies: ["EslCore"]),
        .testTarget(name: "EslCoreTests", dependencies: ["EslCore"]),
    ],
    swiftLanguageModes: [.v5]
)
