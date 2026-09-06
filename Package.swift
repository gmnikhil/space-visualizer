// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Resonant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Resonant", targets: ["ResonantApp"])
    ],
    targets: [
        .target(
            name: "ResonantCore",
            path: "Sources/ResonantCore",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "ResonantApp",
            dependencies: ["ResonantCore"],
            path: "Sources/ResonantApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "ResonantCoreTests",
            dependencies: ["ResonantCore"],
            path: "Tests/ResonantCoreTests"
        ),
        .testTarget(
            name: "ResonantUITests",
            dependencies: ["ResonantCore"],
            path: "Tests/ResonantUITests"
        )
    ]
)
