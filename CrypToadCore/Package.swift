// swift-tools-version: 5.9
import PackageDescription

// Pure-Swift business logic for CrypToad: money math, allocations, round-ups,
// DCA scheduling, the local ledger, persistence, and market-data decoding.
// It has no UIKit/SwiftUI dependency, so it builds and tests on macOS and Linux.
let package = Package(
    name: "CrypToadCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CrypToadCore", targets: ["CrypToadCore"])
    ],
    targets: [
        .target(name: "CrypToadCore"),
        .testTarget(
            name: "CrypToadCoreTests",
            dependencies: ["CrypToadCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
