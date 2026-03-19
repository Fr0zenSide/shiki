// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CoreKit",
            targets: ["CoreKit"]
        ),
    ],
    targets: [
        .target(
            name: "CoreKit"
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"]
        ),
    ]
)
