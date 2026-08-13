// swift-tools-version: 6.0
// SPIKE — throwaway code. Answers: "Swift + swift-subprocess로 simctl 제어가 안정적인가"
import PackageDescription

let package = Package(
    name: "SpikeIOS",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SpikeIOS",
            dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]
        )
    ]
)
