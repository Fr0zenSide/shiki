// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShikkiMCP",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ShikkiMCP",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "ShikkiMCPTests",
            dependencies: ["ShikkiMCP"]
        ),
    ]
)
