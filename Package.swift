// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "bffdotfm-menu-bar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BFFCore",
            resources: [.copy("Resources/coolrock.svg")]
        ),
        .executableTarget(
            name: "BFFMenuBar",
            dependencies: ["BFFCore"]
        ),
        .testTarget(
            name: "BFFCoreTests",
            dependencies: ["BFFCore"]
        ),
    ]
)
