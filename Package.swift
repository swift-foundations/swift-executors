// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-executors",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "Executors", targets: ["Executors"]),
    ],
    dependencies: [
        .package(path: "../swift-kernel"),
        // MUST depend on "Thread Synchronization" product only, never "Threads"
        // (umbrella) or "Thread Pool" — those back-depend on Executors and
        // would create a package-level cycle.
        .package(path: "../swift-threads"),
        .package(path: "../../swift-primitives/swift-executor-primitives"),
    ],
    targets: [
        .target(
            name: "Executors",
            dependencies: [
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Thread Synchronization", package: "swift-threads"),
                .product(name: "Executor Primitives", package: "swift-executor-primitives"),
            ]
        ),
        .testTarget(
            name: "Executor Tests",
            dependencies: [
                "Executors",
                .product(name: "Kernel Test Support", package: "swift-kernel"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
