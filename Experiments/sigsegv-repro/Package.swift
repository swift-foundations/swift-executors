// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "sigsegv-repro",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../../swift-primitives/swift-tagged-primitives"),
        .package(path: "../../../../swift-primitives/swift-ordinal-primitives"),
        .package(path: "../../../../swift-primitives/swift-cardinal-primitives"),
    ],
    targets: [
        .executableTarget(
            name: "sigsegv-repro",
            dependencies: [
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(name: "Ordinal Primitives", package: "swift-ordinal-primitives"),
                .product(name: "Cardinal Primitives", package: "swift-cardinal-primitives"),
            ]
        )
    ]
)

for target in package.targets {
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
    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
