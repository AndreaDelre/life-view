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
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "GoogleAuth",
            dependencies: [
                "Core",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ],
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
