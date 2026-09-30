// swift-tools-version: 6.0
import PackageDescription

/// Pure-Swift financial engine: evidence → observation → reconciliation →
/// canonical ledger → categorization → aggregation. No UI, no persistence,
/// no network, no AI. Runs and tests on macOS without a simulator.
let package = Package(
    name: "LedgerCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "LedgerCore", targets: ["LedgerCore"])],
    targets: [
        .target(name: "LedgerCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
