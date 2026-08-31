// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Lang4Self",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "Lang4SelfCore", targets: ["Lang4SelfCore"]),
        .executable(name: "Lang4Self", targets: ["Lang4Self"]),
        .executable(name: "Lang4SelfDictionaryImporter", targets: ["Lang4SelfDictionaryImporter"]),
        .executable(name: "lang4self", targets: ["Lang4SelfCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", exact: "0.1.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "0.8.1")
    ],
    targets: [
        .target(
            name: "Lang4SelfCore",
            path: "Sources/Lang4SelfCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Lang4Self",
            dependencies: [
                "Lang4SelfCore",
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift")
            ],
            path: "Apps/macOS/Lang4Self",
            exclude: ["Resources/Info.plist", "Resources/AppIcon-1024.png"],
            resources: [.process("Resources/Assets.xcassets")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Translation")
            ]
        ),
        .executableTarget(
            name: "Lang4SelfDictionaryImporter",
            dependencies: ["Lang4SelfCore"],
            path: "Tools/DictionaryImporter"
        ),
        .executableTarget(
            name: "Lang4SelfCLI",
            dependencies: ["Lang4SelfCore"],
            path: "Tools/CLI"
        ),
        .testTarget(
            name: "Lang4SelfCoreTests",
            dependencies: ["Lang4SelfCore"],
            path: "Tests/Lang4SelfCoreTests"
        ),
        .testTarget(
            name: "Lang4SelfAppTests",
            dependencies: ["Lang4Self"],
            path: "Tests/Lang4SelfAppTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
