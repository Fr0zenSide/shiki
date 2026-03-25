// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DataKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "DataKit",
            targets: ["DataKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tursodatabase/libsql-swift.git", from: "0.1.1"),
    ],
    targets: [
        .target(
            name: "DataKit",
            dependencies: [
                .product(name: "Libsql", package: "libsql-swift"),
            ]
        ),
        .testTarget(
            name: "DataKitTests",
            dependencies: ["DataKit"]
        ),
    ]
)
