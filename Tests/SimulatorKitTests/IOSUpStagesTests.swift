import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
private let bootedUDID = "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5"
private let builtApp = "/Users/USER/Library/Developer/Xcode/DerivedData/"
    + "MyApp-havbflbgvamctbaxyteuotyyandn/Build/Products/Debug-iphonesimulator/MyApp.app"
private let builtBundleID = "com.example.MyApp"

/// A clone that has already been through an `up`: dependencies installed, and the
/// machine's simulator booted. Everything the second run is supposed to skip.
private func settledProject() throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", #"{"dependencies": {"react-native": "0.81.0"}}"#)
    try repo.write("yarn.lock", "")
    try repo.directory("node_modules")
    try repo.directory("ios/MyApp.xcodeproj")
    return repo
}

private func destination(_ repo: FixtureRepo) -> String {
    "-project \(repo.url("ios/MyApp.xcodeproj").path) -scheme MyApp -configuration Debug "
        + "-destination platform=iOS Simulator,id=\(bootedUDID)"
}

private func buildCommand(_ repo: FixtureRepo) -> String { "xcodebuild \(destination(repo)) build" }
private let installCommand = "xcrun simctl install \(bootedUDID) \(builtApp)"
private let terminateCommand = "xcrun simctl terminate \(bootedUDID) \(builtBundleID)"
private let launchCommand = "xcrun simctl launch \(bootedUDID) \(builtBundleID)"

/// Every command the seven stages send on a clean run, answered with the machine's
/// own captured output wherever there is a fixture for it.
private func runner(_ repo: FixtureRepo) throws -> FakeProcessRunner {
    FakeProcessRunner(responses: [
        // validate
        "xcode-select -p": .ok(developerDirectory + "\n"),
        "xcodebuild -version": .ok(try Fixture.text("xcodebuild-version.stdout.txt")),
        "xcrun simctl list runtimes -j": .ok(try Fixture.text("simctl-list-runtimes.stdout.json")),
        "node --version": .ok("v22.14.0\n"),
        "yarn --version": .ok("1.22.22\n"),
        // device — the captured list has this machine's one simulator, booted
        "xcrun simctl list devices -j": .ok(try Fixture.text("simctl-list-devices.stdout.json")),
        // metro — this project's own, named by the header `/status` carries
        MetroStatus.command: .ok(MetroStatus.running(projectRoot: repo.root)),
        // build
        "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(
            #"{"project": {"name": "MyApp", "schemes": ["MyApp"]}}"#
        ),
        buildCommand(repo): .ok("** BUILD SUCCEEDED **\n"),
        "xcodebuild -showBuildSettings -json \(destination(repo))": .ok(
            try Fixture.text("xcodebuild-showbuildsettings.stdout.json")
        ),
        // install / launch
        installCommand: .ok(""),
        terminateCommand: .ok(""),
        launchCommand: .ok(try Fixture.text("simctl-launch.stdout.txt")),
    ])
}

private func pipeline(_ repo: FixtureRepo, _ runner: FakeProcessRunner) -> UpPipeline {
    let anchor = ProjectAnchor.detect(from: repo.root)!
    let config = ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)
    let lookup = MatrixLookup.resolve(anchor: anchor, config: config.configuration)
    let locator = XcodeLocator(runner: runner, developerDirOverride: nil)
    return UpPipeline(
        stages: iOSUpStages(
            anchor: anchor,
            doctor: DoctorEngine(
                checks: iOSChecks(lookup: lookup, runner: runner, locator: locator)
                    + configChecks(context: config, lookup: lookup, runner: runner, locator: locator)
                    + anchor.checks(runner: runner)
            ),
            config: config,
            lookup: lookup,
            runner: runner,
            locator: locator,
            // The wait exists for a human watching the screen; a test would only spend
            // three seconds per run on it.
            readinessWait: .zero,
            note: { _ in }
        )
    )
}

/// Everything under the repo, so a stage that wrote into it is caught by name.
private func contents(of repo: FixtureRepo) -> Set<String> {
    let files = FileManager.default.enumerator(atPath: repo.root.path)?.allObjects as? [String] ?? []
    return Set(files)
}

@Suite("up pipeline on iOS")
struct IOSUpStagesTests {
    /// The whole North Star in one assertion: a settled project goes through all
    /// seven stages and the run ends with the app launched and exit 0.
    @Test("the seven stages run in order and the run ends with the app launched")
    func allSeven() async throws {
        let repo = try settledProject()
        let runner = try runner(repo)

        let report = await pipeline(repo, runner).run()

        #expect(
            report.stages.map(\.id) == [
                "validate", "dependencies", "device", "metro", "build", "install", "launch",
            ]
        )
        #expect(report.exitCode == 0)
        #expect(report.context.device?.udid == bootedUDID)
        #expect(report.context.product?.bundleIdentifier == builtBundleID)
        #expect(report.context.metro?.state == .reused)
        #expect(report.context.appPid == 3538)
    }

    /// "Run it again" is the whole recovery procedure, so the second run has to be
    /// cheap where the first was expensive — and still relaunch, because what is on
    /// the screen when `up` returns is the code it just built.
    @Test("a second run skips what is already done and launches the app again anyway")
    func rerunSkipsButRelaunches() async throws {
        let repo = try settledProject()
        let runner = try runner(repo)

        _ = await pipeline(repo, runner).run()
        let second = await pipeline(repo, runner).run()

        #expect(second.exitCode == 0)
        let skipped = second.stages.filter { $0.status == .skipped }.map(\.id)
        #expect(skipped == ["dependencies", "device", "metro"])
        // Nothing was reinstalled, nothing was rebooted, no second bundler.
        let sent = runner.log.all.map(\.description)
        #expect(sent.contains { $0.contains("bootstatus") } == false)
        #expect(sent.contains { $0.hasPrefix("yarn install") } == false)
        #expect(runner.log.spawned.isEmpty)
        // Launch, on the other hand, went out on both runs.
        #expect(sent.filter { $0 == launchCommand }.count == 2)
        #expect(sent.filter { $0 == terminateCommand }.count == 2)
        #expect(second.context.appPid == 3538)
    }

    /// No cache, no state file, no lock of mobile's own: each stage is cheap enough to
    /// repeat that none is needed, which is what makes the invalidation bugs
    /// impossible rather than handled.
    ///
    /// The project directory is what this checks, because it is the only place such a
    /// file could be both written and read back per checkout. Run logs go to the
    /// system temporary directory on purpose (`RunLogs`) and are named in the output.
    @Test("a run leaves nothing of mobile's own behind in the project")
    func writesNothingIntoTheProject() async throws {
        let repo = try settledProject()
        let runner = try runner(repo)
        let before = contents(of: repo)

        _ = await pipeline(repo, runner).run()

        #expect(contents(of: repo) == before)
    }

    /// The project's problem exits 1, and the stages behind the failure never ran —
    /// which is the only way "it stopped" can be observed from outside.
    @Test("a failed build stops before install and exits 1")
    func domainFailureExitsOne() async throws {
        let repo = try settledProject()
        var runner = try runner(repo)
        runner.responses[buildCommand(repo)] = .failed(65, "error: no such module 'React'\n")

        let report = await pipeline(repo, runner).run()

        #expect(report.exitCode == 1)
        #expect(report.stages.map(\.id).last == "build")
        let sent = runner.log.all.map(\.description)
        #expect(sent.contains(installCommand) == false)
        #expect(sent.contains(launchCommand) == false)
        // Failure is not rollback: the booted simulator is the next run's head start.
        #expect(sent.contains { $0.contains("shutdown") || $0.contains("uninstall") } == false)
    }

    /// The other axis: a tool that could not be run at all is not the project's
    /// fault, and a script separates the two by exit code alone.
    @Test("a process that cannot be run at all exits 2")
    func toolFailureExitsTwo() async throws {
        let repo = try settledProject()
        var runner = try runner(repo)
        runner.failures[installCommand] = ProcessError.timedOut(
            command: installCommand, timeout: .seconds(120)
        )

        let report = await pipeline(repo, runner).run()

        #expect(report.exitCode == 2)
        #expect(report.failure?.message.contains("install") == true)
        #expect(runner.log.all.map(\.description).contains(launchCommand) == false)
    }
}
