import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import SimulatorKit
import TestSupport
import Testing

@Suite("Flutter native child boundaries")
struct FlutterIOSRuntimeTests {
    @Test("ordinary source directory aliases stop before native build", arguments: ["lib/shared", "ios", "assets"])
    func sourceDirectoryAlias(_ relative: String) async throws {
        let f = try FlutterIOSFixture()
        let outside = try FixtureRepo()
        let link = f.repo.url(relative)
        let target = outside.url("directory")
        let observed: URL
        if relative == "ios" {
            try FileManager.default.moveItem(at: link, to: target)
            observed = target.appendingPathComponent("Podfile.lock")
        } else {
            try outside.directory("directory")
            observed = try outside.write("directory/shared.dart", "void shared() {}\n")
        }
        let before = try Data(contentsOf: observed)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        let enteredBuild = runner.commands.contains { $0.arguments.last == "build" }
        print("#208 directory alias receipt: source=\(relative); workflowExit=\(result.exitCode); nativeBuild=\(enteredBuild)")
        #expect(result.exitCode == 1)
        #expect(!enteredBuild)
        #expect(try Data(contentsOf: observed) == before)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test("an explicitly selected SDK directory alias retains its exact identity", arguments: ["FLUTTER_ROOT", "PATH"])
    func declaredSDKAlias(_ declaration: String) async throws {
        let f = try FlutterIOSFixture()
        try f.repo.directory("tools")
        let alias = f.repo.url("tools/flutter")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.repo.url("sdk"))
        var environment = f.flutter.environment
        environment.removeValue(forKey: "FLUTTER_ROOT")
        environment[declaration] = declaration == "PATH" ? alias.appendingPathComponent("bin").path + ":/usr/bin:/bin" : alias.path + "/"
        let input = WorkflowInput(project: ProjectInspectionInput(directory: f.app, environment: environment, platform: .ios))
        let result = await WorkflowExecution.run(.build, input: input, runner: FlutterIOSRunner(fixture: f), leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == f.repo.url("sdk").path)
    }

    @Test("SDK and plugin alias exceptions require both the verified source path and target", arguments: ["sdk-target", "sdk-path", "plugin-target", "plugin-name"])
    func directoryAliasIdentity(_ mode: String) async throws {
        let f = try FlutterIOSFixture()
        let plugin = try FixtureRepo()
        let unrelated = try FixtureRepo()
        try unrelated.write("preserve", "owned temporary source\n")
        try f.configureIOSPlugin(directory: plugin.root)
        let relative = mode == "sdk-path" ? "tools/flutter" : mode == "sdk-target" ? ".fvm/flutter_sdk"
            : "ios/.symlinks/plugins/" + (mode == "plugin-name" ? "unverified" : "owned_plugin")
        let alias = f.repo.url(relative)
        try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = mode == "sdk-path" ? f.repo.url("sdk") : mode == "plugin-name" ? plugin.root : unrelated.root
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == target.path)
        #expect(try String(contentsOf: unrelated.url("preserve"), encoding: .utf8) == "owned temporary source\n")
    }

    @Test("current inspection and the stage guard reject changed plugin metadata and source", arguments: ["before-metadata", "between-metadata", "between-missing", "after-metadata", "after-source"])
    func aliasEvidenceChanges(_ mode: String) async throws {
        let f = try FlutterIOSFixture()
        let plugin = try FixtureRepo()
        try f.configureIOSPlugin(directory: plugin.root)
        try f.repo.directory("ios/.symlinks/plugins")
        try FileManager.default.createSymbolicLink(at: f.repo.url("ios/.symlinks/plugins/owned_plugin"), withDestinationURL: plugin.root)
        let preparation = try await FlutterPreparation.inspect(directory: f.app, environment: f.flutter.environment, runner: f.flutter.runner())
        let candidate = try #require(f.input().project.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
        let changed = mode == "after-source" ? "lib/main.dart" : ".flutter-plugins-dependencies"
        if mode == "before-metadata" {
            try f.repo.write(changed, "changed metadata")
            let runner = FlutterIOSRunner(fixture: f)
            let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
            #expect(result.exitCode == 1)
            #expect(!runner.commands.contains { $0.arguments.last == "build" })
        } else if mode == "between-missing" {
            try FileManager.default.removeItem(at: plugin.root)
            #expect(throws: DomainError.self) {
                try FlutterIOSWorkflow(anchor: anchor, input: f.input().project, preparation: preparation, runner: f.flutter.runner())
            }
            #expect(!FileManager.default.fileExists(atPath: plugin.root.path))
        } else if mode == "between-metadata" {
            let unrelated = try FixtureRepo()
            let row: [String: Any] = ["name": "owned_plugin", "path": unrelated.root.path, "native_build": true]
            try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": ["ios": [row], "android": []]])
                .write(to: f.repo.url(changed))
            let alias = f.repo.url("ios/.symlinks/plugins/owned_plugin")
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: unrelated.root)
            #expect(throws: DomainError.self) {
                try FlutterIOSWorkflow(anchor: anchor, input: f.input().project, preparation: preparation, runner: f.flutter.runner())
            }
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == unrelated.root.path)
            return
        } else {
            let workflow = try FlutterIOSWorkflow(anchor: anchor, input: f.input().project, preparation: preparation, runner: f.flutter.runner())
            try f.repo.write(changed, "changed source")
            #expect(throws: DomainError.self) { try workflow.check() }
            #expect(try String(contentsOf: f.repo.url(changed), encoding: .utf8) == "changed source")
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: f.repo.url("ios/.symlinks/plugins/owned_plugin").path) == plugin.root.path)
    }

    @Test("regular-file and unresolved source symlinks stop before a native child", arguments: ["ios/Podfile.lock", "lib/shared.dart", "lib/broken.dart", "lib/cycle.dart"])
    func externalSourceSymlink(_ relative: String) async throws {
        let f = try FlutterIOSFixture()
        let outside = try FixtureRepo()
        let before = relative.hasSuffix(".lock") ? "PODS:\n  - Flutter (1.0.0)\n" : "void shared() {}\n"
        let file = try outside.write("external-source", before)
        let link = f.repo.url(relative)
        if FileManager.default.fileExists(atPath: link.path) { try FileManager.default.removeItem(at: link) }
        let target = relative == "lib/broken.dart" ? outside.url("missing") : relative == "lib/cycle.dart" ? link : file
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let inspection = try await EnvironmentInspection.run(input: f.input().project, runner: FlutterIOSRunner(fixture: f))
        #expect(inspection.report.checks.contains { $0.id == "ios.flutter.generated" && $0.status == .pass })
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        let message = try #require(result.up?.failure?.message)
        #expect(message.contains(relative))
        #expect(!message.contains(outside.root.path))
        #expect(!message.contains(f.repo.root.path))
        #expect(result.operation.nextAction?.contains("manually") == true)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
        #expect(try String(contentsOf: file, encoding: .utf8) == before)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        print("#208 symlink rejection receipt: source=\(relative); workflowExit=\(result.exitCode); nativeBuild=false")
    }

    @Test("the actual native child profile preserves source and SDK payload while allowing derived output")
    func childWriteBoundary() async throws {
        let f = try FlutterIOSFixture()
        let preparation = try await FlutterPreparation.inspect(directory: f.repo.root,
            environment: f.flutter.environment, runner: f.flutter.runner())
        let candidate = try #require(f.input().project.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
        let workflow = try FlutterIOSWorkflow(anchor: anchor, input: f.input().project,
            preparation: preparation, runner: f.flutter.runner())
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": f.repo.url("home").path], workingDirectory: f.repo.root)
        for relative in ["pubspec.lock", "lib/main.dart", "sdk/bin/cache/flutter_tools.snapshot"] {
            let file = f.repo.url(relative)
            let before = try Data(contentsOf: file)
            let result = try await runner.run(ProcessCommand("/usr/bin/sandbox-exec",
                ["-f", workflow.childProfile.path, "/bin/sh", "-c", "printf changed > \"$1\"", "_", file.path], timeout: .seconds(10)))
            #expect(!result.terminationStatus.isSuccess, Comment(rawValue: relative + " " + result.combinedOutput))
            #expect(try Data(contentsOf: file) == before, Comment(rawValue: relative))
        }
        let output = f.repo.url(".dart_tool/child-generated")
        let generated = try await runner.run(ProcessCommand("/usr/bin/sandbox-exec",
            ["-f", workflow.childProfile.path, "/bin/sh", "-c", "printf generated > \"$1\"", "_", output.path], timeout: .seconds(10)))
        #expect(generated.terminationStatus.isSuccess)
        #expect(try String(contentsOf: output, encoding: .utf8) == "generated")
        try workflow.check()
    }

    @Test("workflow cancellation terminates its actual temporary child before returning and never installs")
    func actualCancellation() async throws {
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["CFFIXED_USER_HOME"] {
            let expected = URL(fileURLWithPath: configured)
            #expect(try FolderIdentity(directory: FileManager.default.homeDirectoryForCurrentUser) == FolderIdentity(directory: expected))
            #expect(environment["HOME"] == configured)
            #expect(ResourceLeases.user.directory == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/dev.runstir/leases"))
            print("#208 test-bundle isolation: HOME=\(environment["HOME"] ?? "nil"); FoundationHome=\(FileManager.default.homeDirectoryForCurrentUser.path); LeaseRoot=\(ResourceLeases.user.directory.path)")
        }
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "real-child")
        let input = f.input()
        let leases = f.leases
        let task = Task { await WorkflowExecution.run(.up, input: input, runner: runner, leases: leases) }
        let marker = f.repo.url("build/child.pid")
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        let result = await task.value
        #expect(result.exitCode == 130, Comment(rawValue: result.up?.failure?.message ?? ""))
        let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
        #expect(!runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") })
        let owner = LeaseOwner(operationId: "next", command: "build", project: f.repo.root.path)
        let lease = try f.leases.acquire([.folder(FolderIdentity(directory: f.repo.root)), .device(.ios, "A")], owner: owner)
        lease.release()
    }

    @Test("a successful app PID without a service URI is not development readiness")
    func missingURI() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "no-uri")
        let locator = XcodeLocator(runner: runner)
        var context = UpContext()
        context.device = SelectedDevice(name: "iPhone A", udid: "A", runtime: "27.0")
        context.product = BuiltProduct(path: "/test/Runner.app", bundleIdentifier: "dev.test.flutter")
        do {
            _ = try await LaunchStage(project: f.repo.root, runner: runner, locator: locator,
                readinessWait: .milliseconds(10), flutterPort: 12345).run(&context)
            Issue.record("missing URI must fail")
        } catch is DomainError {
            #expect(context.appPid == 3538)
            #expect(context.developmentServiceURI == nil)
        }
    }

    @Test("an unvalidated tuple stays unknown in the shared Flutter validation stage")
    func unknownTuple() async throws {
        let report = await UpPipeline(stages: [ValidateStage(engine: DoctorEngine(checks: [UnknownFlutterTuple()]),
            checkIDs: IOSWorkflowValidation.checkIDs)]).run()
        #expect(report.exitCode == 0)
        #expect(report.context.validation?.checks.first?.status == .unknown)
        #expect(report.status == .unknown)
    }

    @Test("SDK and generated plugin directory aliases remain usable while SDK link deletion is detected")
    func sdkAlias() async throws {
        let f = try FlutterIOSFixture()
        let plugin = try FixtureRepo()
        try f.configureIOSPlugin(directory: plugin.root)
        let pluginManifest = try Data(contentsOf: plugin.url("pubspec.yaml"))
        try f.repo.directory("ios/.symlinks/plugins")
        let pluginAlias = f.repo.url("ios/.symlinks/plugins/owned_plugin")
        try FileManager.default.createSymbolicLink(at: pluginAlias, withDestinationURL: plugin.root)
        try f.repo.directory(".fvm")
        let alias = f.repo.url(".fvm/flutter_sdk")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.repo.url("sdk"))
        let preparation = try await FlutterPreparation.inspect(directory: f.repo.root,
            environment: f.flutter.environment, runner: f.flutter.runner())
        let candidate = try #require(f.input().project.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
        let workflow = try FlutterIOSWorkflow(anchor: anchor, input: f.input().project,
            preparation: preparation, runner: f.flutter.runner())
        let runner = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": f.repo.url("home").path], workingDirectory: f.repo.root)
        let remove = try await runner.run(ProcessCommand("/usr/bin/sandbox-exec",
            ["-f", workflow.childProfile.path, "/bin/rm", alias.path], timeout: .seconds(10)))
        #expect(!remove.terminationStatus.isSuccess)
        try workflow.check()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: pluginAlias.path) == plugin.root.path)
        #expect(try Data(contentsOf: plugin.url("pubspec.yaml")) == pluginManifest)
        try FileManager.default.removeItem(at: alias)
        #expect(throws: DomainError.self) { try workflow.check() }
        #expect(!FileManager.default.fileExists(atPath: alias.path))
    }
}

private struct UnknownFlutterTuple: Check {
    let id = "xcode.version"
    let category = "Flutter iOS"
    let title = "Validation tuple"
    func run() async throws -> CheckOutcome { .unknown(reason: "This tuple has no validation evidence.") }
}
