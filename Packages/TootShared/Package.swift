// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TootShared",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TootShared", targets: ["TootShared"]),
        // Kept as its own library (not folded into TootShared) so the
        // widget, which also links TootShared, doesn't drag PostHog in.
        .library(name: "ToodAnalytics", targets: ["ToodAnalytics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.92.0"),
    ],
    targets: [
        .target(name: "TootShared"),
        .target(
            name: "ToodAnalytics",
            dependencies: [.product(name: "PostHog", package: "posthog-ios")]
        ),
    ]
)
