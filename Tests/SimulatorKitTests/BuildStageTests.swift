import Core
import Foundation
import TestSupport
import Testing

@testable import SimulatorKit

private let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
private let packageJSON = #"{"dependencies": {"react-native": "0.81.0"}}"#
private let udid = "61DECACB-3D94-4748-B5A2-E7A1EB97E6D5"

private func schemeList(_ schemes: [String]) -> String {
    #"{"project": {"name": "MyApp", "schemes": [\#(schemes.map { "\"\($0)\"" }.joined(separator: ","))]}}"#
}

/// The shape of `-showBuildSettings -json`, cut down to the four keys the decoder
/// reads. The whole document is pinned by the captured fixture; this is for the
/// target combinations one machine's project cannot produce.
private func buildSettings(_ targets: (name: String, product: String)...) -> String {
    let entries = targets.map { target in
        #"""
        {"action": "build", "target": "\#(target.name)", "buildSettings": {
            "BUILT_PRODUCTS_DIR": "/Build/Products/Debug-iphonesimulator",
            "FULL_PRODUCT_NAME": "\#(target.product)",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.example.\#(target.name)"
        }}
        """#
    }
    return "[\(entries.joined(separator: ","))]"
}

/// A React Native project with an Xcode project in `ios/`, and a workspace beside it
/// when the scenario is a CocoaPods one.
private func project(workspace: Bool, mobileYML: String? = nil) throws -> FixtureRepo {
    let repo = try FixtureRepo()
    try repo.write("package.json", packageJSON)
    try repo.directory("ios/MyApp.xcodeproj")
    if workspace { try repo.directory("ios/MyApp.xcworkspace") }
    if let mobileYML { try repo.write("mobile.yml", mobileYML) }
    return repo
}

private func target(_ repo: FixtureRepo, workspace: Bool) -> String {
    workspace
        ? "-workspace \(repo.url("ios/MyApp.xcworkspace").path)"
        : "-project \(repo.url("ios/MyApp.xcodeproj").path)"
}

private func buildCommand(_ repo: FixtureRepo, workspace: Bool, scheme: String) -> String {
    "xcodebuild \(target(repo, workspace: workspace)) -scheme \(scheme) -configuration Debug "
        + "-destination platform=iOS Simulator,id=\(udid) build"
}

private func settingsCommand(_ repo: FixtureRepo, workspace: Bool, scheme: String) -> String {
    "xcodebuild -showBuildSettings -json \(target(repo, workspace: workspace)) -scheme \(scheme) "
        + "-configuration Debug -destination platform=iOS Simulator,id=\(udid)"
}

private func runner(
    _ repo: FixtureRepo,
    workspace: Bool,
    schemes: [String],
    scheme: String,
    build: FakeProcessRunner.Response = .ok("** BUILD SUCCEEDED **\n")
) throws -> FakeProcessRunner {
    FakeProcessRunner(responses: [
        "xcode-select -p": .ok(developerDirectory + "\n"),
        "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)": .ok(schemeList(schemes)),
        buildCommand(repo, workspace: workspace, scheme: scheme): build,
        settingsCommand(repo, workspace: workspace, scheme: scheme): .ok(
            try Fixture.text("xcodebuild-showbuildsettings.stdout.json")
        ),
    ])
}

/// A build that does not finish until the elapsed line has been printed twice. The
/// test then asserts what it means — the line appears *while* the build runs —
/// rather than racing a wall clock on a loaded machine. The deadline is there so a
/// ticker that never fires fails the test instead of hanging it.
private struct BlockingRunner: ProcessRunner {
    let inner: FakeProcessRunner
    let notes: Mutable<[String]>
    let until: Int

    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        if command.arguments.last == "build" {
            let deadline = ContinuousClock.now + .seconds(5)
            while notes.value.count < until, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        return try await inner.run(command)
    }

    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
        try await inner.spawnDetached(command, logFile: logFile)
    }
}

/// A context as the pipeline hands it to `build`: `device` has already run.
private func afterDevice() -> UpContext {
    var context = UpContext()
    context.device = SelectedDevice(name: "iPhone 17 Pro", udid: udid, runtime: "26.5")
    return context
}

private func temporaryLogs() throws -> RunLogs {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("mobile-buildstage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    return RunLogs(project: URL(fileURLWithPath: "/a/MyApp"), temporaryDirectory: temporary)
}

@discardableResult
private func run(
    _ repo: FixtureRepo,
    _ runner: FakeProcessRunner,
    context: inout UpContext,
    logs: RunLogs? = nil
) async throws -> StageOutcome {
    let configuration = ConfigContext.detect(
        anchor: ProjectAnchor.detect(from: repo.root), workingDirectory: repo.root
    )
    let stage = BuildStage(
        config: configuration,
        runner: runner,
        locator: XcodeLocator(runner: runner, developerDirOverride: nil),
        logs: try logs ?? temporaryLogs(),
        note: { _ in }
    )
    return try await stage.run(&context)
}

@Suite("build stage")
struct BuildStageTests {
    /// CocoaPods links through the workspace; building the project instead is how a
    /// React Native app fails at link time with nothing to read.
    @Test("a workspace is what xcodebuild is pointed at when there is one")
    func workspaceWins() async throws {
        let repo = try project(workspace: true)
        let runner = try runner(repo, workspace: true, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        let outcome = try await run(repo, runner, context: &context)

        #expect(outcome.status == .pass)
        #expect(runner.log.first(matching: buildCommand(repo, workspace: true, scheme: "MyApp")) != nil)
        // The scheme list is still read off the project: a workspace answers with
        // every Pod scheme it contains.
        #expect(
            runner.log.all.map(\.description).contains(
                "xcodebuild -list -json -project \(repo.url("ios/MyApp.xcodeproj").path)"
            )
        )
    }

    @Test("without a workspace the project is built directly")
    func projectFallback() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        let outcome = try await run(repo, runner, context: &context)

        #expect(outcome.status == .pass)
        #expect(runner.log.first(matching: buildCommand(repo, workspace: false, scheme: "MyApp")) != nil)
    }

    /// Zero-config: one scheme is not a choice, so nothing has to be declared.
    @Test("the only scheme is used without a declaration")
    func singleScheme() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        #expect(try await run(repo, runner, context: &context).detail == "MyApp")
    }

    @Test("mobile.yml's scheme is the one built")
    func declaredScheme() async throws {
        let repo = try project(workspace: false, mobileYML: "ios:\n  scheme: MyApp-tvOS\n")
        let runner = try runner(
            repo, workspace: false, schemes: ["MyApp", "MyApp-tvOS"], scheme: "MyApp-tvOS"
        )
        var context = afterDevice()

        let outcome = try await run(repo, runner, context: &context)

        #expect(outcome.detail == "MyApp-tvOS")
        #expect(runner.log.first(matching: buildCommand(repo, workspace: false, scheme: "MyApp-tvOS")) != nil)
    }

    /// The other half of the cross: the two decisions — what to point xcodebuild at,
    /// and which scheme to name — are independent, and a CocoaPods project with
    /// several schemes is the ordinary React Native shape.
    @Test("a workspace and a declared scheme are decided independently")
    func workspaceWithDeclaredScheme() async throws {
        let repo = try project(workspace: true, mobileYML: "ios:\n  scheme: MyApp-tvOS\n")
        let runner = try runner(
            repo, workspace: true, schemes: ["MyApp", "MyApp-tvOS"], scheme: "MyApp-tvOS"
        )
        var context = afterDevice()

        let outcome = try await run(repo, runner, context: &context)

        #expect(outcome.detail == "MyApp-tvOS")
        #expect(runner.log.first(matching: buildCommand(repo, workspace: true, scheme: "MyApp-tvOS")) != nil)
    }

    /// Two workspaces is not "no workspace". Falling through to the project would
    /// build the one target CocoaPods cannot link and blame the code for it.
    @Test("more than one workspace stops the run instead of falling back to the project")
    func ambiguousWorkspace() async throws {
        let repo = try project(workspace: true)
        try repo.directory("ios/MyApp-Other.xcworkspace")
        let runner = try runner(repo, workspace: true, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("ios") == true)
        #expect(runner.log.all.map(\.description).contains { $0.hasSuffix("build") } == false)
    }

    /// doctor warns about this and carries on; up cannot. The tool does not pick one
    /// of a project's schemes on the developer's behalf (ADR-0004).
    @Test("several schemes and no declaration stops the run")
    func undecidedScheme() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(
            repo, workspace: false, schemes: ["MyApp", "MyApp-tvOS"], scheme: "MyApp"
        )
        var context = afterDevice()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("MyApp, MyApp-tvOS") == true)
        #expect(error?.remediation.summary.contains("mobile.yml") == true)
        #expect(error?.remediation.command == "xcodebuild -list -project ios/MyApp.xcodeproj")
        // Nothing was built, so nothing may claim to have been.
        #expect(context.product == nil)
        #expect(runner.log.all.map(\.description).contains { $0.hasSuffix("build") } == false)
    }

    /// `config.values` grades this first, so up only reaches it when mobile.yml
    /// changed under a running command — and then it says what it could not find.
    @Test("a declared scheme the project does not define stops the run")
    func declaredSchemeMissing() async throws {
        let repo = try project(workspace: false, mobileYML: "ios:\n  scheme: Ghost\n")
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("no scheme named Ghost") == true)
    }

    /// The contract of the whole stage, read off the command line it produced: Debug,
    /// the udid `device` chose, no derived data override, and no timeout to kill a
    /// slow machine's first clean build.
    @Test("the build is Debug, on the chosen udid, with Xcode's own derived data and no timeout")
    func buildCommandShape() async throws {
        let repo = try project(workspace: true)
        let runner = try runner(repo, workspace: true, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        try await run(repo, runner, context: &context)
        let build = try #require(runner.log.first(matching: buildCommand(repo, workspace: true, scheme: "MyApp")))

        #expect(build.arguments.contains("-derivedDataPath") == false)
        #expect(build.timeout == nil)
        #expect(build.environment["DEVELOPER_DIR"] == developerDirectory)
    }

    /// Read from `-showBuildSettings`, not from the build log: log formats move
    /// between Xcode versions and this is what install has to pick up.
    @Test("the app path and bundle id come from the build settings")
    func product() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        var context = afterDevice()

        try await run(repo, runner, context: &context)

        #expect(
            context.product?.path == "/Users/USER/Library/Developer/Xcode/DerivedData/"
                + "MyApp-havbflbgvamctbaxyteuotyyandn/Build/Products/Debug-iphonesimulator/MyApp.app"
        )
        #expect(context.product?.bundleIdentifier == "com.example.MyApp")
    }

    /// The whole point of writing the log: the reader gets the last lines on screen
    /// and a path to the rest, instead of a terminal buffer to scroll through.
    @Test("a failed build writes the full log and names the file")
    func failureWritesLog() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(
            repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp",
            // xcodebuild's diagnostics go to stdout and its own noise to stderr,
            // which is why the tail cannot be taken from stderr alone.
            build: FakeProcessRunner.Response(
                status: .exited(65),
                standardOutput: "AppDelegate.swift:9:1: error: cannot find 'Foo' in scope\n"
                    + "** BUILD FAILED **\n",
                standardError: "[MT] IDERunDestination: nothing useful here\n"
            )
        )
        let logs = try temporaryLogs()
        var context = afterDevice()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context, logs: logs)
        }

        let file = logs.directory.appendingPathComponent("build.log")
        #expect(error?.remediation.summary.contains(file.path) == true)
        // Pasteable as printed: the destination carries a space, and a line that has
        // to be repaired before it runs is not a remediation.
        #expect(
            error?.remediation.command?.hasSuffix("-destination 'platform=iOS Simulator,id=\(udid)' build")
                == true
        )
        #expect(error?.observed?.contains("cannot find 'Foo' in scope") == true)
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("** BUILD FAILED **"))
        #expect(written.contains("cannot find 'Foo' in scope"))
        #expect(context.product == nil)
    }

    /// A failed build has no product to describe, and asking for one would only add
    /// a second failure on top of the one worth reading.
    @Test("a failed build never asks for build settings")
    func failureStopsBeforeSettings() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(
            repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp",
            build: .failed(65, "error: no such module 'React'\n")
        )
        var context = afterDevice()

        _ = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(runner.log.all.map(\.description).contains { $0.contains("-showBuildSettings") } == false)
    }

    /// Not a `DomainError`: a project with no `ios/` Xcode project is a real project
    /// problem, but a build with no device is the pipeline run out of order.
    @Test("building before a device was chosen is a tool failure")
    func withoutDevice() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        var context = UpContext()

        await #expect(throws: ToolUnavailable.self) {
            try await run(repo, runner, context: &context)
        }
    }

    /// The build is the one step long enough for silence to read as a hang. Output
    /// stays collected (ADR-0002) — this line says the tool is alive, nothing more.
    @Test("an elapsed line is printed while the build runs")
    func elapsedWhileBuilding() async throws {
        let repo = try project(workspace: false)
        let runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        let notes = Mutable<[String]>([])
        let configuration = ConfigContext.detect(
            anchor: ProjectAnchor.detect(from: repo.root), workingDirectory: repo.root
        )
        let stage = BuildStage(
            config: configuration,
            runner: BlockingRunner(inner: runner, notes: notes, until: 2),
            locator: XcodeLocator(runner: runner, developerDirOverride: nil),
            logs: try temporaryLogs(),
            heartbeat: .milliseconds(10),
            note: { line in notes.value.append(line) }
        )
        var context = afterDevice()

        try await stage.run(&context)

        #expect(notes.value.count >= 2)
        #expect(notes.value.allSatisfy { $0.hasPrefix("build") && $0.contains("running…") })
    }

    /// `-showBuildSettings` answers for every target the scheme builds, and a scheme
    /// that builds a UI-test host answers with two `.app`s. Handing install whichever
    /// one came first is the coin-flip `SchemeSelector` refuses to make.
    @Test("two app bundles and no target of the scheme's name is not guessed between")
    func ambiguousProduct() async throws {
        let repo = try project(workspace: false)
        var runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        runner.responses[settingsCommand(repo, workspace: false, scheme: "MyApp")] = .ok(
            buildSettings(("App", "App.app"), ("TestHost", "TestHost.app"))
        )
        var context = afterDevice()

        await #expect(throws: ToolUnavailable.self) {
            try await run(repo, runner, context: &context)
        }
        #expect(context.product == nil)
    }

    /// Scheme and target names are independent in Xcode, but when they do agree that
    /// is the answer — no counting required.
    @Test("the target named like the scheme wins over the other app bundles")
    func productByTargetName() async throws {
        let repo = try project(workspace: false)
        var runner = try runner(repo, workspace: false, schemes: ["MyApp"], scheme: "MyApp")
        runner.responses[settingsCommand(repo, workspace: false, scheme: "MyApp")] = .ok(
            buildSettings(("TestHost", "TestHost.app"), ("MyApp", "MyApp.app"))
        )
        var context = afterDevice()

        try await run(repo, runner, context: &context)

        #expect(context.product?.path.hasSuffix("/MyApp.app") == true)
    }

    @Test("no Xcode project in ios/ stops the run with something to do about it")
    func noTarget() async throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", packageJSON)
        try repo.directory("ios")
        let runner = FakeProcessRunner(responses: [
            "xcode-select -p": .ok(developerDirectory + "\n"),
            "xcodebuild -version": .ok("Xcode 26.6\nBuild version 17F113\n"),
        ])
        var context = afterDevice()

        let error = await #expect(throws: DomainError.self) {
            try await run(repo, runner, context: &context)
        }

        #expect(error?.summary.contains("ios") == true)
    }
}
