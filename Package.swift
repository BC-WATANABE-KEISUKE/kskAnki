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
        ),
        .executable(
            name: "kskAnkiVerifier",
            targets: ["kskAnkiVerifier"]
        )
    ],
    targets: [
        .target(
            name: "kskAnkiCore",
            path: "src"
        ),
        .executableTarget(
            name: "kskAnkiVerifier",
            dependencies: ["kskAnkiCore"],
            path: "tests"
        )
    ]
)
