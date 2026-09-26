// swift-tools-version: 6.2
import PackageDescription

/// The `klm` command-line tool lives in its own package, outside
/// Packages/KelidKit, so that iOS builds of the app/keyboard targets never
/// try to build this macOS-only executable (PLAN.md §4.2, task 0.5).
let package = Package(
    name: "klm",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../Packages/KelidKit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "klm",
            dependencies: [
                .product(name: "PredictionEngine", package: "KelidKit"),
                .product(name: "PersianText", package: "KelidKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "klmTests",
            dependencies: [
                "klm",
                .product(name: "PredictionEngine", package: "KelidKit"),
                .product(name: "PersianText", package: "KelidKit"),
                .product(name: "KelidCore", package: "KelidKit"),
            ]
        ),
    ]
)
