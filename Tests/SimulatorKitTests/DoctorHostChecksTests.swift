import Core
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"

private func engine(_ runner: FakeProcessRunner, developerDirOverride: String? = nil) -> DoctorEngine {
    let locator = XcodeLocator(runner: runner, developerDirOverride: developerDirOverride)
    return DoctorEngine(checks: [
        XcodeInstalledCheck(locator: locator),
        SimulatorDaemonCheck(runner: runner, locator: locator),
    ])
}

@Suite("xcode.installed")
struct XcodeInstalledCheckTests {
    @Test("passes when xcode-select points at a full Xcode")
    func installed() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok(try Fixture.text("xcodebuild-version.stdout.txt")),
            "xcrun simctl list runtimes -j": .ok(try Fixture.text("simctl-list-runtimes.stdout.json")),
        ])

        let report = await engine(runner).run(only: ["xcode.installed"])
        let check = try #require(report.checks.first)

        #expect(check.id == "xcode.installed")
        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("Xcode 26.6 (17F113)") == true)
        #expect(check.outcome.observed?.contains(developerDirectory) == true)
        #expect(check.outcome.remediation == nil)
    }

    @Test("errors when only Command Line Tools are selected")
    func commandLineToolsOnly() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/Library/Developer/CommandLineTools\n"),
            "xcodebuild -version": .failed(1, try Fixture.text("xcodebuild-version-commandlinetools.stderr.txt")),
        ])

        let report = await engine(runner).run(only: ["xcode.installed"])
        let check = try #require(report.checks.first)

        #expect(check.status == .error)
        #expect(check.outcome.remediation?.command == "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer")
        #expect(report.hasToolFailure == false)
    }

    @Test("errors when DEVELOPER_DIR points nowhere")
    func brokenDeveloperDir() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcodebuild -version": .failed(1, try Fixture.text("xcodebuild-version-broken-developer-dir.stderr.txt"))
        ])

        let report = await engine(runner, developerDirOverride: "/tmp/nope").run(only: ["xcode.installed"])
        let check = try #require(report.checks.first)

        #expect(check.status == .error)
        #expect(check.outcome.remediation != nil)
        // DEVELOPER_DIR wins over xcode-select, so xcode-select is never consulted.
        #expect(runner.log.first(matching: "xcode-select -p") == nil)
        #expect(runner.log.first(matching: "xcodebuild -version")?.environment["DEVELOPER_DIR"] == "/tmp/nope")
    }

    @Test("errors when there is no active developer directory")
    func noDeveloperDirectory() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .failed(2, "xcode-select: error: unable to get active developer directory\n")
        ])

        let report = await engine(runner).run(only: ["xcode.installed"])
        let check = try #require(report.checks.first)

        #expect(check.status == .error)
        #expect(check.outcome.remediation?.url == "https://developer.apple.com/xcode/")
    }

    @Test("a timeout is a tool failure, not a domain verdict")
    func timeoutIsToolFailure() async throws {
        var runner = FakeProcessRunner(responses: [:])
        runner.failures["xcode-select -p"] = ProcessError.timedOut(command: "xcode-select -p", timeout: .seconds(15))

        let report = await engine(runner).run(only: ["xcode.installed"])
        let check = try #require(report.checks.first)

        #expect(check.status == .unknown)
        #expect(report.hasToolFailure)
    }
}

@Suite("simulator.daemon")
struct SimulatorDaemonCheckTests {
    @Test("passes when simctl answers, with DEVELOPER_DIR pinned to the located Xcode")
    func daemonResponds() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok(try Fixture.text("xcodebuild-version.stdout.txt")),
            "xcrun simctl list runtimes -j": .ok(try Fixture.text("simctl-list-runtimes.stdout.json")),
        ])

        let report = await engine(runner).run()
        let check = try #require(report.checks.first { $0.id == "simulator.daemon" })

        #expect(check.status == .pass)
        #expect(check.outcome.observed?.contains("1 of 1 runtimes available") == true)
        #expect(
            runner.log.first(matching: "xcrun simctl list runtimes -j")?.environment["DEVELOPER_DIR"]
                == developerDirectory
        )
        #expect(report.status == .pass)
    }

    @Test("errors when simctl exits non-zero")
    func daemonUnreachable() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok(try Fixture.text("xcodebuild-version.stdout.txt")),
            "xcrun simctl list runtimes -j": .failed(72, try Fixture.text("simctl-commandlinetools.stderr.txt")),
        ])

        let report = await engine(runner).run()
        let check = try #require(report.checks.first { $0.id == "simulator.daemon" })

        #expect(check.status == .error)
        #expect(check.outcome.remediation?.command == "killall -9 com.apple.CoreSimulator.CoreSimulatorService")
        #expect(report.status == .error)
    }

    @Test("errors when simctl answers with something that is not a runtime list")
    func daemonGibberish() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok(try Fixture.text("xcodebuild-version.stdout.txt")),
            "xcrun simctl list runtimes -j": .ok("not json"),
        ])

        let report = await engine(runner).run()
        let check = try #require(report.checks.first { $0.id == "simulator.daemon" })

        #expect(check.status == .error)
    }

    @Test("is unknown — not a second error — when Xcode could not be located")
    func unknownWhenXcodeMissing() async throws {
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok("/Library/Developer/CommandLineTools\n"),
            "xcodebuild -version": .failed(1, try Fixture.text("xcodebuild-version-commandlinetools.stderr.txt")),
        ])

        let report = await engine(runner).run()
        let daemon = try #require(report.checks.first { $0.id == "simulator.daemon" })

        #expect(daemon.status == .unknown)
        #expect(daemon.outcome.reason?.contains("xcode.installed") == true)
        #expect(runner.log.first(matching: "xcrun simctl list runtimes -j") == nil)
    }
}
