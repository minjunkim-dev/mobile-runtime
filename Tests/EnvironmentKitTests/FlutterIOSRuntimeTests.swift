import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import SimulatorKit
import Testing

@Suite("Flutter native child boundaries")
struct FlutterIOSRuntimeTests {
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
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

    @Test("an SDK alias link deletion is blocked and an unexpected deletion is reported")
    func sdkAlias() async throws {
        let f = try FlutterIOSFixture()
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
