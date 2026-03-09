// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesignKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DesignKit",
            targets: ["DesignKit"]
        )
    ],
    targets: [
        .target(
            name: "DesignKit"
        ),
        .testTarget(
            name: "DesignKitTests",
            dependencies: ["DesignKit"]
        )
    ]
)
