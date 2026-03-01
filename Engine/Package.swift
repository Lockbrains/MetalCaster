// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MetalCaster",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "MetalCasterCore", targets: ["MetalCasterCore"]),
        .library(name: "MetalCasterRenderer", targets: ["MetalCasterRenderer"]),
        .library(name: "MetalCasterScene", targets: ["MetalCasterScene"]),
        .library(name: "MetalCasterAsset", targets: ["MetalCasterAsset"]),
        .library(name: "MetalCasterInput", targets: ["MetalCasterInput"]),
        .library(name: "MetalCasterPhysics", targets: ["MetalCasterPhysics"]),
        .library(name: "MetalCasterAudio", targets: ["MetalCasterAudio"]),
        .library(name: "MetalCasterAI", targets: ["MetalCasterAI"]),
    ],
    targets: [
        // ── Core Engine Libraries ──────────────────────────────────
        .target(
            name: "MetalCasterCore",
            path: "Sources/MetalCasterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterRenderer",
            dependencies: ["MetalCasterCore"],
            path: "Sources/MetalCasterRenderer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterScene",
            dependencies: ["MetalCasterCore", "MetalCasterRenderer"],
            path: "Sources/MetalCasterScene",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterAsset",
            dependencies: ["MetalCasterCore", "MetalCasterRenderer"],
            path: "Sources/MetalCasterAsset",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterInput",
            path: "Sources/MetalCasterInput",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterPhysics",
            dependencies: ["MetalCasterCore", "MetalCasterScene"],
            path: "Sources/MetalCasterPhysics",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterAudio",
            dependencies: ["MetalCasterCore"],
            path: "Sources/MetalCasterAudio",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MetalCasterAI",
            path: "Sources/MetalCasterAI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // ── App Targets ────────────────────────────────────────────
        .executableTarget(
            name: "MetalCasterEditor",
            dependencies: [
                "MetalCasterCore",
                "MetalCasterRenderer",
                "MetalCasterScene",
                "MetalCasterAsset",
                "MetalCasterAI",
            ],
            path: "Apps/MetalCasterEditor/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MCRuntime",
            dependencies: [
                "MetalCasterCore",
                "MetalCasterRenderer",
                "MetalCasterScene",
                "MetalCasterInput",
                "MetalCasterPhysics",
                "MetalCasterAudio",
            ],
            path: "Apps/MCRuntime/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // ── Tests ──────────────────────────────────────────────────
        .testTarget(
            name: "MetalCasterCoreTests",
            dependencies: ["MetalCasterCore"],
            path: "Tests/MetalCasterCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
