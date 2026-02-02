// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawLauncher",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "OpenClawLauncher",
            path: "Sources"
        )
    ]
)

