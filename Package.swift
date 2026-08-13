// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mobile",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mobile", targets: ["mobile"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Foundation-only. No Apple frameworks — the boundary that keeps Android
        // viable later. Enforced by CoreImportDisciplineTests.
        .target(
            name: "Core",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        // iOS domain knowledge: Xcode location, simctl, iOS checks.
        .target(
            name: "SimulatorKit",
            dependencies: [
                "Core",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "mobile",
            dependencies: [
                "Core",
                "SimulatorKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(
            name: "SimulatorKitTests",
            dependencies: ["SimulatorKit", "Core"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
