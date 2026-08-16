import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
private let udid = "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5"
private let bundleID = "net.cozic.joplin"
private let terminateCommand = "xcrun simctl terminate \(udid) \(bundleID)"

private func runner(_ responses: [String: FakeProcessRunner.Response]) -> FakeProcessRunner {
    FakeProcessRunner(
        responses: responses.merging([
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        ]) { scenario, _ in scenario }
    )
}

private func teardown(_ runner: FakeProcessRunner, _ logs: RunLogs) -> AppTeardown {
    AppTeardown(
        logs: logs, runner: runner, locator: XcodeLocator(runner: runner, developerDirOverride: nil)
    )
}

@Suite("app teardown")
struct AppTeardownTests {
    /// The record is the only path to "which app, on which device" — a simulator
    /// does not say which app is ours, and recomputing needs a scheme (ADR-0007).
    @Test("the app named by the install record is terminated on the device it names")
    func terminatesTheRecordedApp() async throws {
        let logs = try RunLogs.temporary()
        InstallRecord(udid: udid, bundleId: bundleID).write(to: logs)
        let runner = runner([terminateCommand: .ok("")])

        let item = await teardown(runner, logs).run()

        #expect(item.status == .stopped)
        #expect(item.detail?.contains(bundleID) == true)
        let sent = runner.log.all.map(\.description)
        #expect(sent.contains(terminateCommand))
        // down stops the app; it does not remove it, and the record still describes
        // what is installed.
        #expect(sent.contains { $0.contains("uninstall") } == false)
        #expect(InstallRecord.read(from: logs) != nil)
    }

    /// A record, not a cache: when it is missing the app is skipped and said to be
    /// skipped, rather than recomputed from a scheme the project may not declare.
    @Test("no install record is a skip with the reason, not a recomputation")
    func withoutARecord() async throws {
        let runner = runner([:])

        let item = await teardown(runner, try RunLogs.temporary()).run()

        #expect(item.status == .skipped)
        #expect(item.detail == "no install record — nothing to stop")
        #expect(runner.log.all.map(\.description).contains { $0.contains("simctl") } == false)
    }

    /// `launch` already made this judgement for the same command: an app that was
    /// not running is not a failure to stop it. What simctl said is repeated rather
    /// than interpreted — "it was not running" is the usual reason, not the only one.
    @Test("a terminate simctl refused is not a failure, and is not explained away")
    func terminateRefused() async throws {
        let logs = try RunLogs.temporary()
        InstallRecord(udid: udid, bundleId: bundleID).write(to: logs)
        let runner = runner([terminateCommand: .failed(3, "No matching processes belonging to you")])

        let item = await teardown(runner, logs).run()

        #expect(item.status == .skipped)
        #expect(item.detail?.contains("was not stopped") == true)
        #expect(item.detail?.contains("No matching processes") == true)
    }

    /// The other half of ignoring it: a terminate that could not run at all must not
    /// become `down`'s exit 2 either.
    @Test("a terminate that could not run at all is not a failure")
    func terminateToolFailure() async throws {
        let logs = try RunLogs.temporary()
        InstallRecord(udid: udid, bundleId: bundleID).write(to: logs)
        var runner = runner([:])
        runner.failures[terminateCommand] = ProcessError.timedOut(
            command: terminateCommand, timeout: .seconds(30)
        )

        let item = await teardown(runner, logs).run()

        #expect(item.status == .skipped)
    }
}

@Suite("ios teardown")
struct IOSTeardownTests {
    /// Both halves, in one report, neither depending on the other. The simulator is
    /// not in the set — `up` may have booted it, but it is the machine's resource.
    @Test("down aims at this project's Metro and its app, and at nothing else")
    func bothJobs() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.81.0"}}"#)
        try repo.write("yarn.lock", "")
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let logs = try RunLogs.temporary()
        InstallRecord(udid: udid, bundleId: bundleID).write(to: logs)
        let runner = runner([
            MetroStatus.command: .failed(7, ""),
            terminateCommand: .ok(""),
        ])

        let report = await iOSTeardown(
            anchor: anchor, runner: runner, locator: XcodeLocator(runner: runner, developerDirOverride: nil),
            logs: logs, grace: .zero
        ).run()

        #expect(report.items.map(\.id) == ["metro", "app"])
        #expect(report.items.map(\.status) == [.skipped, .stopped])
        #expect(report.exitCode == 0)
        let sent = runner.log.all.map(\.description)
        #expect(sent.contains { $0.contains("shutdown") || $0.contains("boot") } == false)
    }
}
