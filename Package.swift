// swift-tools-version: 6.3.1

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
        .package(path: "../swift-synchronizers"),
        .package(path: "../../swift-primitives/swift-executor-primitives"),
        .package(path: "../../swift-primitives/swift-property-primitives"),
        .package(path: "../../swift-primitives/swift-ordinal-primitives"),
        .package(path: "../../swift-primitives/swift-index-primitives"),
        .package(path: "../../swift-primitives/swift-cpu-primitives"),
    ],
    targets: [
        .target(
            name: "Executors",
            dependencies: [
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Synchronizer Blocking", package: "swift-synchronizers"),
                .product(name: "Executor Primitives", package: "swift-executor-primitives"),
                .product(name: "Property Primitives", package: "swift-property-primitives"),
                .product(name: "Ordinal Primitives", package: "swift-ordinal-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "CPU Primitives", package: "swift-cpu-primitives"),
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
