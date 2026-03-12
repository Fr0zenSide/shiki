// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MediaKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MediaKit",
            targets: ["MediaKit"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../NetworkKit"),
        .package(path: "../SecurityKit"),
    ],
    targets: [
        .target(
            name: "MediaKit",
            dependencies: [
                "CoreKit",
                .product(name: "NetKit", package: "NetworkKit"),
                "SecurityKit",
            ]
        ),
        .testTarget(
            name: "MediaKitTests",
            dependencies: ["MediaKit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
