// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShikkiKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ShikkiKit",
            targets: ["ShikkiKit"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "ShikkiKit",
            dependencies: ["CoreKit"]
        ),
        .testTarget(
            name: "ShikkiKitTests",
            dependencies: ["ShikkiKit"]
        ),
    ]
)
