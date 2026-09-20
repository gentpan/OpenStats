// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStatsKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Localization", targets: ["Localization"]),
        .library(name: "SMC", targets: ["SMC"]),
        .library(name: "Metrics", targets: ["Metrics"]),
        .library(name: "HelperShared", targets: ["HelperShared"]),
        .library(name: "Cleaner", targets: ["Cleaner"]),
        .library(name: "Updates", targets: ["Updates"]),
        .library(name: "AccountSync", targets: ["AccountSync"]),
        .library(name: "OpenStatsUI", targets: ["OpenStatsUI"]),
    ],
    targets: [
        .target(name: "Localization"),
        .target(name: "SMC", dependencies: ["Localization"]),
        .target(name: "Metrics", dependencies: ["SMC", "Localization"], linkerSettings: [.linkedLibrary("IOReport")]),
        .target(name: "HelperShared", dependencies: ["Localization"]),
        .target(name: "Cleaner", dependencies: ["Localization"]),
        .target(name: "Updates", dependencies: ["Localization"]),
        .target(name: "AccountSync", dependencies: ["Localization"]),
        .target(name: "OpenStatsUI", dependencies: ["Localization", "Metrics", "SMC", "HelperShared", "Cleaner", "Updates", "AccountSync"],
                resources: [.copy("Resources/Flags"), .copy("Resources/Logos")]),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics", "SMC"]),
        .testTarget(name: "CleanerTests", dependencies: ["Cleaner"]),
        .testTarget(name: "HelperSharedTests", dependencies: ["HelperShared"]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
        .testTarget(name: "AccountSyncTests", dependencies: ["AccountSync"]),
        .testTarget(name: "OpenStatsUITests", dependencies: ["OpenStatsUI", "Metrics", "AccountSync"]),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
    ],
    swiftLanguageModes: [.v6]
)
