// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yami",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "YamiShared", path: "Sources/YamiShared"),
        .executableTarget(
            name: "Yami",
            dependencies: ["Yams", "YamiShared"],
            path: "Sources/Yami"
        ),
        .testTarget(
            name: "YamiTests",
            dependencies: ["Yami", "Yams"],
            path: "Tests/YamiTests"
        ),
        // Runs as root under launchd. Nothing here may depend on the app.
        .executableTarget(
            name: "YamiHelper",
            dependencies: ["YamiShared"],
            path: "Sources/YamiHelper"
        ),
    ]
)
