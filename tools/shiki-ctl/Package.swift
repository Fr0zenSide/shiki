// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "shikki",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shikki", targets: ["shikki"]),
        .library(name: "ShikiCtlKit", targets: ["ShikiCtlKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ShikiCtlKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "shikki",
            dependencies: [
                "ShikiCtlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "ShikiCtlKitTests",
            dependencies: ["ShikiCtlKit"]
        ),
        .testTarget(
            name: "ShikiCtlTests",
            dependencies: [
                "shikki",
                "ShikiCtlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
