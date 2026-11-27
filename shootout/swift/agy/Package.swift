// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mj",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "mj",
            path: "Sources/mj"
        )
    ]
)
