// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KelidKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "KelidCore", targets: ["KelidCore"]),
        .library(name: "KelidSettings", targets: ["KelidSettings"]),
        .library(name: "PersianText", targets: ["PersianText"]),
        .library(name: "KeyboardLayout", targets: ["KeyboardLayout"]),
        .library(name: "InputEngine", targets: ["InputEngine"]),
        .library(name: "PredictionEngine", targets: ["PredictionEngine"]),
        .library(name: "KelidStorage", targets: ["KelidStorage"]),
        .library(name: "ClipboardKit", targets: ["ClipboardKit"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
        .library(name: "EmojiData", targets: ["EmojiData"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.17.0"),
    ],
    targets: [
        // MARK: - KelidCore

        .target(
            name: "KelidCore"
        ),
        .testTarget(
            name: "KelidCoreTests",
            dependencies: ["KelidCore"]
        ),

        // MARK: - KelidSettings

        .target(
            name: "KelidSettings",
            dependencies: ["KelidCore"]
        ),
        .testTarget(
            name: "KelidSettingsTests",
            dependencies: ["KelidSettings"]
        ),

        // MARK: - PersianText

        .target(
            name: "PersianText"
        ),
        .testTarget(
            name: "PersianTextTests",
            dependencies: ["PersianText"]
        ),

        // MARK: - KeyboardLayout

        .target(
            name: "KeyboardLayout",
            dependencies: ["KelidCore", "KelidSettings"],
            resources: [.process("Layouts")]
        ),
        .testTarget(
            name: "KeyboardLayoutTests",
            dependencies: ["KeyboardLayout"]
        ),

        // MARK: - InputEngine

        .target(
            name: "InputEngine",
            dependencies: ["PersianText", "KeyboardLayout", "KelidSettings"]
        ),
        .testTarget(
            name: "InputEngineTests",
            dependencies: ["InputEngine"]
        ),

        // MARK: - PredictionEngine

        .target(
            name: "PredictionEngine",
            dependencies: [
                "PersianText",
                "KelidCore",
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        .testTarget(
            name: "PredictionEngineTests",
            dependencies: ["PredictionEngine"]
        ),

        // MARK: - KelidStorage

        .target(
            name: "KelidStorage",
            dependencies: [
                "KelidCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "KelidStorageTests",
            dependencies: ["KelidStorage"]
        ),

        // MARK: - ClipboardKit

        .target(
            name: "ClipboardKit",
            dependencies: ["KelidStorage", "PersianText", "KelidCore"]
        ),
        .testTarget(
            name: "ClipboardKitTests",
            dependencies: ["ClipboardKit"]
        ),

        // MARK: - ThemeKit

        .target(
            name: "ThemeKit",
            dependencies: ["KelidCore"],
            resources: [.process("BuiltInThemes")]
        ),
        .testTarget(
            name: "ThemeKitTests",
            dependencies: ["ThemeKit"]
        ),

        // MARK: - EmojiData

        .target(
            name: "EmojiData",
            dependencies: ["PersianText"],
            resources: [.process("emoji.json")]
        ),
        .testTarget(
            name: "EmojiDataTests",
            dependencies: ["EmojiData"]
        ),

        // MARK: - KeyboardUI

        .target(
            name: "KeyboardUI",
            dependencies: [
                "KelidCore",
                "KelidSettings",
                "PersianText",
                "KeyboardLayout",
                "InputEngine",
                "PredictionEngine",
                "KelidStorage",
                "ClipboardKit",
                "ThemeKit",
                "EmojiData",
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "KeyboardUITests",
            dependencies: [
                "KeyboardUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
