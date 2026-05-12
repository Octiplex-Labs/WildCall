// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WildCallCore",
    defaultLocalization: "fr",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "WildCallCoreShared", targets: ["WildCallCoreShared"]),
        .library(name: "WildCallCoreApp", targets: ["WildCallCoreApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "4.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.4.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
    ],
    targets: [
        // Shared between app and Call Directory Extension.
        // Constraints: no network, minimal RAM, no heavy deps (no PhoneNumberKit, no TCA).
        .target(
            name: "WildCallCoreShared",
            dependencies: [
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            ]
        ),
        // App-only: full feature set (expansion, parsing, sync, signatures).
        .target(
            name: "WildCallCoreApp",
            dependencies: [
                "WildCallCoreShared",
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ]
        ),
        .testTarget(
            name: "WildCallCoreSharedTests",
            dependencies: [
                "WildCallCoreShared",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .testTarget(
            name: "WildCallCoreAppTests",
            dependencies: [
                "WildCallCoreApp",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
