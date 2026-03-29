// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brainy",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BrainyCore", targets: ["BrainyCore"]),
        .library(name: "BrainyTubeKit", targets: ["BrainyTubeKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BrainyCore",
            path: "Sources/BrainyCore"
        ),
        .target(
            name: "BrainyTubeKit",
            dependencies: ["BrainyCore"],
            path: "Sources/BrainyTube"
        ),
        .testTarget(
            name: "BrainyTubeTests",
            dependencies: ["BrainyCore", "BrainyTubeKit"],
            path: "Tests/BrainyTubeTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
