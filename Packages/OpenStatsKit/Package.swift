// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStatsKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SMC", targets: ["SMC"]),
        .library(name: "Metrics", targets: ["Metrics"]),
        .library(name: "HelperShared", targets: ["HelperShared"]),
        .library(name: "Cleaner", targets: ["Cleaner"]),
        .library(name: "Updates", targets: ["Updates"]),
        .library(name: "OpenStatsUI", targets: ["OpenStatsUI"]),
    ],
    targets: [
        .target(name: "SMC"),
        .target(name: "Metrics", dependencies: ["SMC"]),
        .target(name: "HelperShared"),
        .target(name: "Cleaner"),
        .target(name: "Updates"),
        .target(name: "OpenStatsUI", dependencies: ["Metrics", "SMC", "HelperShared", "Cleaner", "Updates"],
                resources: [.copy("Resources/Flags")]),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics", "SMC"]),
        .testTarget(name: "CleanerTests", dependencies: ["Cleaner"]),
        .testTarget(name: "HelperSharedTests", dependencies: ["HelperShared"]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
    ],
    swiftLanguageModes: [.v6]
)
