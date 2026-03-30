// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Maya",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MayaKit",
            targets: ["MayaKit"]
        ),
    ],
    targets: [
        .target(
            name: "MayaKit"
        ),
        .testTarget(
            name: "MayaKitTests",
            dependencies: ["MayaKit"]
        ),
    ]
)
