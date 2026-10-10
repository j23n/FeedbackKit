// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeedbackKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // The app-facing library: the gestures, the capture, the form and the settings.
        .library(name: "FeedbackKit", targets: ["FeedbackKit"]),
        // Reports, the outbox and the GitHub client, without any UI; builds on Linux.
        .library(name: "FeedbackCore", targets: ["FeedbackCore"]),
    ],
    targets: [
        .target(name: "FeedbackCore"),
        .target(name: "FeedbackKit", dependencies: ["FeedbackCore"]),
        .testTarget(name: "FeedbackCoreTests", dependencies: ["FeedbackCore"]),
    ]
)
