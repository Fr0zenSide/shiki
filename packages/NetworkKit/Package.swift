// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "NetKit",
            targets: ["NetKit"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(
            name: "NetKit",
            dependencies: ["CoreKit"],
            path: "Sources/NetworkKit"
        ),
        .testTarget(
            name: "NetKitTests",
            dependencies: ["NetKit"],
            path: "Tests/NetworkKitTests"
        ),
    ]
)
