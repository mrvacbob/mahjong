// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "mj",
    products: [
        .library(name: "Riichi", targets: ["Riichi"]),
        .executable(name: "mj", targets: ["mj"]),
    ],
    targets: [
        // The engine: no imports at all, not even Foundation.
        .target(name: "Riichi", path: "Sources/Riichi"),
        // The line protocol (spec/formats.md).
        .executableTarget(name: "mj", dependencies: ["Riichi"], path: "Sources/mj"),
        .testTarget(name: "RiichiTests", dependencies: ["Riichi"], path: "Tests/RiichiTests"),
    ]
)
