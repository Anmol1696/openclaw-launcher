// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawLauncher",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "OpenClawLib",
            path: "Sources/OpenClawLib"
        ),
        .executableTarget(
            name: "OpenClawLauncher",
            dependencies: ["OpenClawLib"],
            path: "Sources/OpenClawApp"
        ),
        .testTarget(
            name: "OpenClawTests",
            dependencies: ["OpenClawLib"],
            path: "Tests/OpenClawTests"
        ),
        .testTarget(
            name: "OpenClawIntegrationTests",
            dependencies: ["OpenClawLib"],
            path: "Tests/OpenClawIntegrationTests"
        ),
    ]
)
