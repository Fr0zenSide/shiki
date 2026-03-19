// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "shiki-ctl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shiki-ctl", targets: ["shiki-ctl"]),
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
            ]
        ),
        .executableTarget(
            name: "shiki-ctl",
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
                "shiki-ctl",
                "ShikiCtlKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
