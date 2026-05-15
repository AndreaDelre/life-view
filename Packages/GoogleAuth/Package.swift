// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleAuth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GoogleAuth", targets: ["GoogleAuth"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "GoogleAuth",
            dependencies: ["Core"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "GoogleAuthTests",
            dependencies: ["GoogleAuth"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
