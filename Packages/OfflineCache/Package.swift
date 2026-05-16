// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OfflineCache",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OfflineCache", targets: ["OfflineCache"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../GoogleAuth"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "OfflineCache",
            dependencies: [
                "Core",
                "GoogleAuth",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "OfflineCacheTests",
            dependencies: ["OfflineCache"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
