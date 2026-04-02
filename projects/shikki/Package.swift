// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "shikki",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shi", targets: ["shi"]),
        .executable(name: "shikki-test", targets: ["shikki-test"]),
        .library(name: "ShikkiKit", targets: ["ShikkiKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(name: "ShikkiTestRunner", path: "../../packages/ShikkiTestRunner"),
    ],
    targets: [
        .target(
            name: "ShikkiKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .copy("Resources/autopilot-prompt.md"),
            ]
        ),
        .executableTarget(
            name: "shi",
            dependencies: [
                "ShikkiKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/shikki"
        ),
        .executableTarget(
            name: "shikki-test",
            dependencies: [
                "ShikkiKit",
                "ShikkiTestRunner",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ShikkiKitTests",
            dependencies: ["ShikkiKit"],
            exclude: ["__Snapshots__"]
        ),
    ]
)
