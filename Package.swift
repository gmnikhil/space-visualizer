// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceVisualizer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpaceVisualizer", targets: ["SpaceVisualizerApp"])
    ],
    targets: [
        .target(
            name: "SpaceVisualizerCore",
            path: "Sources/SpaceVisualizerCore",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "SpaceVisualizerApp",
            dependencies: ["SpaceVisualizerCore"],
            path: "Sources/SpaceVisualizerApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "SpaceVisualizerCoreTests",
            dependencies: ["SpaceVisualizerCore"],
            path: "Tests/SpaceVisualizerCoreTests"
        ),
        .testTarget(
            name: "SpaceVisualizerUITests",
            dependencies: ["SpaceVisualizerCore"],
            path: "Tests/SpaceVisualizerUITests"
        )
    ]
)
