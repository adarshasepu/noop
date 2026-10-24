// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandAnalytics",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "StrandAnalytics", targets: ["StrandAnalytics"])],
    dependencies: [
        .package(path: "../WhoopProtocol"),
        .package(path: "../WhoopStore"),
        // Adarsh's standalone adaptive engine (own folder, own licence TBD); only the bridge below is noop glue.
        .package(path: "../../AdaptiveRecoveryEngine"),
    ],
    targets: [
        .target(name: "StrandAnalytics", dependencies: ["WhoopProtocol", "WhoopStore",
                                                   .product(name: "AdaptiveRecovery", package: "AdaptiveRecoveryEngine")]),
        // WhoopStore is declared on the TEST target as well as the library: the Oura respiration
        // scoring-exclusion tests assert on `OuraRespScale` (the seam that keeps the ring's 0x6A rows
        // out of the stager), and a transitively-visible module is not something a test should rely on.
        .testTarget(name: "StrandAnalyticsTests", dependencies: ["StrandAnalytics", "WhoopStore",
                                                                         .product(name: "AdaptiveRecovery", package: "AdaptiveRecoveryEngine")]),
    ]
)
