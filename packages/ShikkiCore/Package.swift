// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShikkiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShikkiCore", targets: ["ShikkiCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ShikkiCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "ShikkiCoreTests",
            dependencies: ["ShikkiCore"]
        ),
    ]
)
