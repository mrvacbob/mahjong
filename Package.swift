// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "mj",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Riichi", targets: ["Riichi"]),
        .library(name: "RiichiMjai", targets: ["RiichiMjai"]),
        .executable(name: "mj", targets: ["mj"]),
    ],
    targets: [
        // The engine: no imports at all, not even Foundation.
        .target(name: "Riichi", path: "Sources/Riichi"),
        // mjai JSON (design §6): imports only Riichi; its own JSON reader and writer.
        .target(name: "RiichiMjai", dependencies: ["Riichi"], path: "Sources/RiichiMjai"),
        // The line protocol (spec/formats.md), self-play, replay, check-log, bot adapters.
        .executableTarget(name: "mj", dependencies: ["Riichi", "RiichiMjai"], path: "Sources/mj"),
        .testTarget(name: "RiichiTests", dependencies: ["Riichi"], path: "Tests/RiichiTests"),
        .testTarget(name: "RiichiMjaiTests", dependencies: ["Riichi", "RiichiMjai"],
                    path: "Tests/RiichiMjaiTests"),
    ]
)
