// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShikkiTestRunner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShikkiTestRunner", targets: ["ShikkiTestRunner"]),
    ],
    targets: [
        .target(
            name: "ShikkiTestRunner",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "ShikkiTestRunnerTests",
            dependencies: ["ShikkiTestRunner"]
        ),
    ]
)
