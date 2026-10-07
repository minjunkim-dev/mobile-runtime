import Core
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"

private let matrixSource = CheckSource(tier: 2, origin: "compatibility matrix (react-native 0.81)")

private func requirements(xcode: String, runtime: String) -> MatrixLookup {
    MatrixLookup(
        xcode: .requirement(MinimumVersion(xcode)!, source: matrixSource),
        runtime: .requirement(MinimumVersion(runtime)!, source: matrixSource)
    )
}

/// The matrix could not answer either question — the shape every "no measurement,
/// no verdict" scenario starts from.
private func unavailable(_ reason: String) -> MatrixLookup {
    let source = CheckSource(tier: 2, origin: "compatibility matrix")
    return MatrixLookup(
        xcode: .unavailable(reason: reason, source: source),
        runtime: .unavailable(reason: reason, source: source)
    )
}

/// The Tier 2 checks go through the engine so the dependency edges
/// (`xcode.installed`, `simulator.daemon`) are part of every scenario.
private func engine(_ runner: FakeProcessRunner, _ lookup: MatrixLookup) -> DoctorEngine {
    let locator = XcodeLocator(runner: runner, developerDirOverride: nil)
    return DoctorEngine(checks: iOSChecks(lookup: lookup, runner: runner, locator: locator))
}

/// Trimmed to the keys the Checks read; the full captured document lives in
/// `Fixtures/simctl-list-runtimes.stdout.json`.
private func runtimeList(_ runtimes: (name: String, version: String, available: Bool)...) -> String {
    let entries = runtimes.map { runtime in
        """
        {
          "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-\(runtime.version.replacingOccurrences(of: ".", with: "-"))",
          "name": "\(runtime.name)",
          "version": "\(runtime.version)",
          "isAvailable": \(runtime.available)
        }
        """
    }
    return #"{"runtimes": [\#(entries.joined(separator: ","))]}"#
}

private func hostResponses(
    xcodebuild: String = "Xcode 26.6\nBuild version 17F113\n",
    runtimes: String
) -> [String: FakeProcessRunner.Response] {
    [
        "xcode-select -p": .ok(developerDirectory + "\n"),
        "xcodebuild -version": .ok(xcodebuild),
        "xcodebuild -checkFirstLaunchStatus": .ok(""),
        "xcrun simctl list runtimes -j": .ok(runtimes),
    ]
}

@Suite("iOS check assembly")
struct IOSChecksTests {
    /// A new machine with nothing cloned still gets a clean host verdict: the two
    /// Tier 2 lines are absent rather than a permanent `unknown` that would turn
    /// a healthy Xcode into a `?`.
    @Test("outside a project the Tier 2 checks are absent and the host ones still pass")
    func hostOnly() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: try Fixture.text("simctl-list-runtimes.stdout.json"))
        )
        let locator = XcodeLocator(runner: runner, developerDirOverride: nil)

        let report = await DoctorEngine(
            checks: iOSChecks(lookup: nil, runner: runner, locator: locator)
        ).run()

        #expect(report.checks.map(\.id) == ["xcode.installed", "xcode.ready", "simulator.daemon"])
        #expect(report.status == .pass)
    }
}

@Suite("xcode.version")
struct XcodeVersionCheckTests {
    @Test("passes when the installed Xcode clears the matrix floor")
    func compatible() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: try Fixture.text("simctl-list-runtimes.stdout.json"))
        )

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1"))
            .run(only: ["xcode.version"])
        let check = try #require(report.checks.first { $0.id == "xcode.version" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "Xcode 26.6 (17F113)")
        #expect(check.outcome.required == "Xcode 16.1 or newer")
        #expect(check.outcome.source.tier == 2)
    }

    @Test("errors when the installed Xcode is older than this React Native needs")
    func incompatible() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(
                xcodebuild: "Xcode 15.4\nBuild version 15F31d\n",
                runtimes: try Fixture.text("simctl-list-runtimes.stdout.json")
            )
        )

        let report = await engine(runner, requirements(xcode: "26.0", runtime: "15.1"))
            .run(only: ["xcode.version"])
        let check = try #require(report.checks.first { $0.id == "xcode.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed == "Xcode 15.4 (15F31d)")
        #expect(check.outcome.remediation?.summary.contains("Xcode 26.0 or newer") == true)
        #expect(check.outcome.remediation?.url == "https://developer.apple.com/xcode/")
    }

    /// The contract this ticket turns on: no measurement, no verdict.
    @Test("is unknown — never a pass — when the matrix could not answer")
    func dependenciesMissing() async throws {
        let reason = "node_modules is absent, so the installed React Native version could not be "
            + "measured — run `yarn install` first, then re-run mobile doctor"
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: try Fixture.text("simctl-list-runtimes.stdout.json"))
        )

        let report = await engine(runner, unavailable(reason)).run(only: ["xcode.version"])
        let check = try #require(report.checks.first { $0.id == "xcode.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason == reason)
        #expect(check.outcome.remediation == nil)
        #expect(check.outcome.source.tier == 2)
    }

    /// Getting here means `xcode.installed` passed and the matrix (or `.xcode-version`)
    /// already settled a floor, so the requirement is not in doubt — only the Xcode is.
    /// An Xcode that cannot say what version it is cannot be built with, and ADR-0004
    /// grades an unusable tool the project requires as an error.
    @Test("an Xcode whose version cannot be read is an error, not a shrug")
    func unreadableVersion() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(
                xcodebuild: "Xcode beta\nBuild version 17F113\n",
                runtimes: try Fixture.text("simctl-list-runtimes.stdout.json")
            )
        )

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1"))
            .run(only: ["xcode.version"])
        let check = try #require(report.checks.first { $0.id == "xcode.version" })

        #expect(check.status == .error)
        #expect(check.outcome.observed?.contains("`beta`") == true)
        #expect(check.outcome.remediation?.command == "xcodebuild -version")
    }

    @Test("is unknown — not a second error — when Xcode could not be located")
    func xcodeMissing() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/Library/Developer/CommandLineTools\n"),
            "xcodebuild -version": .failed(1, try Fixture.text("xcodebuild-version-commandlinetools.stderr.txt")),
        ])

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1"))
            .run(only: ["xcode.version"])
        let check = try #require(report.checks.first { $0.id == "xcode.version" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason?.contains("xcode.installed") == true)
    }
}

@Suite("simulator.runtime")
struct SimulatorRuntimeCheckTests {
    @Test("passes when an available runtime clears the project's floor")
    func runtimePresent() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: try Fixture.text("simctl-list-runtimes.stdout.json"))
        )

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1")).run()
        let check = try #require(report.checks.first { $0.id == "simulator.runtime" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed == "iOS 26.5 installed and available")
        #expect(check.outcome.required == "an iOS 15.1 or newer simulator runtime, available")
    }

    /// The macOS-update failure: the image is still listed, and useless.
    @Test("errors with the re-mount routine when the runtime is installed but unavailable")
    func runtimeUnavailable() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(
                runtimes: runtimeList(("iOS 26.5", "26.5", false))
            )
        )

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1")).run()
        let check = try #require(report.checks.first { $0.id == "simulator.runtime" })

        #expect(check.status == .error)
        #expect(check.outcome.observed == "iOS 26.5 installed but unavailable")
        #expect(check.outcome.remediation?.command?.contains("runtime scan-and-mount") == true)
    }

    @Test("errors with an install command when every installed runtime is too old")
    func runtimeTooOld() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: runtimeList(("iOS 14.5", "14.5", true)))
        )

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1")).run()
        let check = try #require(report.checks.first { $0.id == "simulator.runtime" })

        #expect(check.status == .error)
        #expect(check.outcome.observed == "installed iOS runtimes: iOS 14.5")
        #expect(check.outcome.remediation?.command == "xcodebuild -downloadPlatform iOS")
    }

    @Test("errors when no iOS runtime is installed at all")
    func noRuntimes() async throws {
        let runner = FakeProcessRunner(responses: hostResponses(runtimes: runtimeList()))

        let report = await engine(runner, requirements(xcode: "16.1", runtime: "15.1")).run()
        let check = try #require(report.checks.first { $0.id == "simulator.runtime" })

        #expect(check.status == .error)
        #expect(check.outcome.observed == "no iOS runtime installed")
    }

    @Test("is unknown, and asks simctl nothing, when the matrix could not answer")
    func dependenciesMissing() async throws {
        let runner = FakeProcessRunner(
            responses: hostResponses(runtimes: try Fixture.text("simctl-list-runtimes.stdout.json"))
        )

        let report = await engine(runner, unavailable("node_modules is absent"))
            .run(only: ["simulator.runtime"])
        let check = try #require(report.checks.first { $0.id == "simulator.runtime" })

        #expect(check.status == .unknown)
        #expect(check.outcome.reason == "node_modules is absent")
        // The daemon check ran (it is a dependency); the runtime check added no call.
        #expect(runner.log.all.filter { $0.description == "xcrun simctl list runtimes -j" }.count == 1)
    }
}
