import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
private let udid = "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5"
private let app = "/Users/USER/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/"
    + "Debug-iphonesimulator/MyApp.app"
private let bundleID = "com.example.MyApp"

private let installCommand = "xcrun simctl install \(udid) \(app)"
private let terminateCommand = "xcrun simctl terminate \(udid) \(bundleID)"
private let launchCommand = "xcrun simctl launch \(udid) \(bundleID)"

/// The context as the pipeline hands it over: `device` and `build` have both run.
private func afterBuild() -> UpContext {
    var context = UpContext()
    context.device = SelectedDevice(name: "iPhone 17 Pro", udid: udid, runtime: "26.5")
    context.product = BuiltProduct(path: app, bundleIdentifier: bundleID)
    return context
}

/// Whatever the scenario answers, plus the two commands the located Xcode costs.
private func runner(_ responses: [String: FakeProcessRunner.Response]) -> FakeProcessRunner {
    FakeProcessRunner(
        responses: responses.merging([
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        ]) { scenario, _ in scenario }
    )
}

private func locator(_ runner: FakeProcessRunner) -> XcodeLocator {
    XcodeLocator(runner: runner, developerDirOverride: nil)
}

private func install(_ runner: FakeProcessRunner, logs: RunLogs? = nil) throws -> InstallStage {
    InstallStage(runner: runner, locator: locator(runner), logs: try logs ?? RunLogs.temporary())
}

@Suite("install stage")
struct InstallStageTests {
    /// simctl replaces the bundle in place. Uninstalling first would take the app's
    /// data with it — a logged-in session is not this stage's to throw away.
    @Test("the app is installed straight over whatever is already there")
    func installsOverTheOldOne() async throws {
        let runner = runner([installCommand: .ok("")])
        var context = afterBuild()

        let outcome = try await install(runner).run(&context)

        #expect(outcome.status == .pass)
        let install = try #require(runner.log.first(matching: installCommand))
        #expect(install.environment["DEVELOPER_DIR"] == developerDirectory)
        let sent = runner.log.all.map(\.description)
        #expect(sent.contains { $0.contains("uninstall") || $0.contains("erase") } == false)
    }

    /// The first moment both halves of "which app, on which device" are settled, and
    /// the only path `down` has to them afterwards — a simulator cannot be asked.
    @Test("a finished install leaves the record down reads")
    func writesTheInstallRecord() async throws {
        let runner = runner([installCommand: .ok("")])
        let logs = try RunLogs.temporary()
        var context = afterBuild()

        _ = try await install(runner, logs: logs).run(&context)

        let record = try #require(InstallRecord.read(from: logs))
        #expect(record.udid == udid)
        #expect(record.bundleId == bundleID)
    }

    @Test("a refused install stops the run with what simctl said and a line to repeat it")
    func refused() async throws {
        let runner = runner([
            installCommand: .failed(2, try Fixture.text("simctl-install-missing.stderr.txt"))
        ])
        var context = afterBuild()

        let error = await #expect(throws: DomainError.self) {
            try await install(runner).run(&context)
        }

        #expect(error?.summary.contains("iPhone 17 Pro") == true)
        #expect(error?.observed?.contains("No such file or directory") == true)
        #expect(error?.remediation.command == installCommand)
    }

    /// The pipeline runs `device` and `build` first. Reaching here without either is
    /// mobile's own bug, so it must not land on the project's exit code.
    @Test("installing before there is anything to install is a tool failure")
    func withoutAProduct() async throws {
        let runner = runner([:])
        var context = UpContext()

        await #expect(throws: ToolUnavailable.self) {
            try await install(runner).run(&context)
        }
    }
}

@Suite("launch stage")
struct LaunchStageTests {
    private func stage(_ runner: FakeProcessRunner, settle: Duration = .zero) -> LaunchStage {
        LaunchStage(runner: runner, locator: locator(runner), settle: settle)
    }

    private func launching(_ output: String = "com.example.MyApp: 3538\n") -> FakeProcessRunner {
        runner([terminateCommand: .ok(""), launchCommand: .ok(output)])
    }

    /// `simctl launch` on an app that is already running hands back the old
    /// instance's pid without restarting it, so the guarantee `up` sells — what is
    /// on screen is the code just built — is bought by the terminate before it.
    @Test("the running instance is terminated before the new one is launched")
    func terminatesFirst() async throws {
        let runner = launching()
        var context = afterBuild()

        let outcome = try await stage(runner).run(&context)

        #expect(outcome.status == .pass)
        let simctl = runner.log.all.map(\.description).filter { $0.contains("simctl") }
        #expect(simctl == [terminateCommand, launchCommand])
    }

    /// "The app was not running" is exit 3 with a paragraph about it, and it is the
    /// ordinary case on a first run — not a reason to stop.
    @Test("a terminate simctl refused does not stop the launch")
    func terminateFailureIsIgnored() async throws {
        let runner = runner([
            terminateCommand: .failed(3, try Fixture.text("simctl-terminate-none.stderr.txt")),
            launchCommand: .ok(try Fixture.text("simctl-launch.stdout.txt")),
        ])
        var context = afterBuild()

        #expect(try await stage(runner).run(&context).status == .pass)
        #expect(context.appPid == 3538)
    }

    /// The other half of ignoring it: a terminate that could not be run at all is
    /// still not news, and it must not become the run's exit 2.
    @Test("a terminate that could not run at all does not stop the launch either")
    func terminateToolFailureIsIgnored() async throws {
        var runner = launching()
        runner.failures[terminateCommand] = ProcessError.timedOut(
            command: terminateCommand, timeout: .seconds(30)
        )
        var context = afterBuild()

        #expect(try await stage(runner).run(&context).status == .pass)
    }

    /// The pid is simctl's own — `com.example.MyApp: 3538` — so a script can go on
    /// from where `up` stopped without looking the app up again.
    @Test("the pid comes off simctl's line and reaches the context")
    func pid() async throws {
        let runner = launching(try Fixture.text("simctl-launch.stdout.txt"))
        var context = afterBuild()

        let outcome = try await stage(runner).run(&context)

        #expect(context.appPid == 3538)
        #expect(outcome.detail?.contains("3538") == true)
        #expect(outcome.detail?.contains(bundleID) == true)
    }

    @Test("a launch simctl refused stops the run")
    func refused() async throws {
        let runner = runner([
            terminateCommand: .ok(""),
            launchCommand: .failed(4, try Fixture.text("simctl-launch-missing.stderr.txt")),
        ])
        var context = afterBuild()

        let error = await #expect(throws: DomainError.self) {
            try await stage(runner).run(&context)
        }

        #expect(error?.observed?.contains("failed to launch") == true)
        #expect(error?.remediation.command == launchCommand)
        #expect(context.appPid == nil)
    }

    /// Not a project problem: simctl said it started the app, and the pid `up`
    /// promises to report is missing from its answer.
    @Test("a launch that prints no pid is a tool failure")
    func noPID() async throws {
        let runner = launching("")
        var context = afterBuild()

        await #expect(throws: ToolUnavailable.self) {
            try await stage(runner).run(&context)
        }
    }

    @Test("launching before there is anything to launch is a tool failure")
    func withoutAProduct() async throws {
        let runner = launching()
        var context = UpContext()

        await #expect(throws: ToolUnavailable.self) {
            try await stage(runner).run(&context)
        }
    }

    /// `simctl launch` returns when the app has been asked to start, not when it has
    /// drawn anything. The wait is injected rather than fixed so a test costs nothing
    /// for it — and so the value can be raised on a machine that needs more.
    @Test("the settle wait is served after the launch")
    func settles() async throws {
        let runner = launching()
        var context = afterBuild()

        let start = ContinuousClock.now
        _ = try await stage(runner, settle: .milliseconds(50)).run(&context)

        #expect(start.duration(to: .now) >= .milliseconds(50))
    }
}
