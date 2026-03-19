// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShikiMCP",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ShikiMCP",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "ShikiMCPTests",
            dependencies: ["ShikiMCP"]
        ),
    ]
)
