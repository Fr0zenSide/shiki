// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShikiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShikiCore", targets: ["ShikiCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ShikiCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "ShikiCoreTests",
            dependencies: ["ShikiCore"]
        ),
    ]
)
