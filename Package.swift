// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mobile",
    // Floor set by swift-subprocess (.macOS(.v13)); nothing here needs more. Only
    // the host Xcode decides what we build with — this is the deployment target.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mobile", targets: ["mobile"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        // Foundation-only. No Apple frameworks — the boundary that keeps Android
        // viable later. Enforced by CoreImportDisciplineTests.
        .target(
            name: "Core",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Logging", package: "swift-log"),
                // mobile.yml is hand-written, so a real YAML parser is what keeps a
                // legal file from being reported as broken.
                .product(name: "Yams", package: "Yams"),
            ],
            // The Tier 2 matrix ships inside the binary: doctor works offline, and a
            // mobile version always carries exactly one matrix.
            resources: [.copy("Resources/matrix.json")]
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
        // The fake ProcessRunner is the project's one injection seam, so both test
        // targets share a single copy of it rather than drifting apart.
        .target(name: "TestSupport", dependencies: ["Core"], path: "Tests/TestSupport"),
        .testTarget(name: "CoreTests", dependencies: ["Core", "TestSupport"]),
        .testTarget(
            name: "SimulatorKitTests",
            dependencies: ["SimulatorKit", "Core", "TestSupport"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
