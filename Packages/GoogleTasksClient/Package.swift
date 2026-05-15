// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleTasksClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GoogleTasksClient", targets: ["GoogleTasksClient"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "GoogleTasksClient",
            dependencies: ["Core"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "GoogleTasksClientTests",
            dependencies: ["GoogleTasksClient"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
