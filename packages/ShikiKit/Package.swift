// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShikiKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ShikiKit",
            targets: ["ShikiKit"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "ShikiKit",
            dependencies: ["CoreKit"]
        ),
        .testTarget(
            name: "ShikiKitTests",
            dependencies: ["ShikiKit"]
        ),
    ]
)
