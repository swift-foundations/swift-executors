// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "realistic-sharded-benchmark",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../../swift-primitives/swift-cpu-primitives"),
    ],
    targets: [
        .executableTarget(
            name: "realistic-sharded-benchmark",
            dependencies: [
                .product(name: "CPU Primitives", package: "swift-cpu-primitives"),
            ]
        )
    ]
)
