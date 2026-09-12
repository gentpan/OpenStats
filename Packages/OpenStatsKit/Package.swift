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
        .library(name: "OpenStatsUI", targets: ["OpenStatsUI"]),
    ],
    targets: [
        .target(name: "SMC"),
        .target(name: "Metrics", dependencies: ["SMC"]),
        .target(name: "HelperShared"),
        .target(name: "OpenStatsUI", dependencies: ["Metrics", "SMC", "HelperShared"]),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics", "SMC"]),
    ],
    swiftLanguageModes: [.v6]
)
