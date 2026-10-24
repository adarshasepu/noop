// swift-tools-version:5.9
import PackageDescription

// AdaptiveRecovery — the per-user adaptive HRV recovery engine (spec: docs/adaptive-recovery/README.md).
// Pure Foundation, no dependency on any other NOOP package, so it builds and tests on Linux, macOS,
// iOS and watchOS alike. StrandAnalytics depends on it and exposes a feature-flagged bridge.
let package = Package(
    name: "AdaptiveRecovery",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "AdaptiveRecovery", targets: ["AdaptiveRecovery"])],
    targets: [
        .target(name: "AdaptiveRecovery",
                resources: [.copy("Resources/params.json")]),
        .testTarget(name: "AdaptiveRecoveryTests",
                    dependencies: ["AdaptiveRecovery"],
                    resources: [.copy("Fixtures")]),
    ]
)
