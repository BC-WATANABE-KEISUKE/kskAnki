// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kskAnki",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "kskAnkiCore",
            targets: ["kskAnkiCore"]
        )
    ],
    targets: [
        .target(
            name: "kskAnkiCore",
            path: "src",
            exclude: ["App"]
        ),
        .testTarget(
            name: "kskAnkiTests",
            dependencies: ["kskAnkiCore"],
            path: "tests"
        )
    ]
)
