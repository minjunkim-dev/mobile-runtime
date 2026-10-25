@testable import AndroidKit
import Core
import Darwin
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("Flutter Android shared protected composition", .serialized)
struct FlutterAndroidWorkflowTests {
    @Test("first offline model, both contexts and assemble reuse one protected project runner")
    func firstModelAndReuse() async throws {
        let fixture = try CallerFixture()
        let preparation = try await fixture.flutter.inspect(fixture.runner)
        #expect(preparation.checks.contains { $0.platform == .ios && $0.kind != "reuse" })
        let trace = Trace()
        let workflow = try await FlutterAndroidWorkflow.make(input: fixture.input, anchor: fixture.anchor,
            runner: fixture.runner, preparation: preparation, tools: fixture.tools, factory: fixture.factory(trace))
        for _ in 0..<2 {
            let context = await WorkflowContext.make(input: fixture.input, platform: .android, anchor: fixture.anchor,
                runner: fixture.runner, includeRuntimeSDKTools: false,
                projectEnvironmentOverride: workflow.projectEnvironment, projectRunnerOverride: workflow.projectRunner)
            #expect(context.androidContext != nil)
            _ = await context.engine.run()
        }
        let build = ProcessCommand("./gradlew", [":app:assembleDebug"], workingDirectory: fixture.flutter.repo.url("android"),
            timeout: nil, output: .collected)
        _ = try await workflow.projectRunner.run(build)
        let gradle = fixture.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(gradle.count >= 3)
        #expect(gradle.first?.arguments.contains("--offline") == true)
        #expect(gradle.allSatisfy { $0.environment["RUNSTIR_FIXTURE_VIEW"] == "same-view"
            && $0.environment["FLUTTER_ROOT"] == fixture.view.path
            && $0.environment["PUB_CACHE"] == preparation.activeEnvironment["PUB_CACHE"] })
        #expect(trace.count == 1)
        #expect(trace.tracked.contains(try Self.physical(fixture.flutter.repo.url("pubspec.lock")).path))
        #expect(try Data(contentsOf: fixture.flutter.repo.url("android/settings.gradle")) == fixture.settings)
        #expect(fixture.runner.log.spawned.isEmpty)
    }

    @Test("an unavailable protected view starts no JDK observation and preserves source")
    func unavailableViewBeforeTools() async throws {
        let fixture = try CallerFixture()
        try fixture.flutter.repo.write("lib/feature.dart", "void feature() {}\n")
        let source = fixture.flutter.repo.url("lib/feature.dart")
        let before = try Data(contentsOf: source)
        let preparation = try await fixture.flutter.inspect(fixture.runner)
        let observed = fixture.runner.log.all.count
        let trace = Trace()
        await #expect(throws: DomainError.self) {
            _ = try await FlutterAndroidWorkflow.make(input: fixture.input, anchor: fixture.anchor,
                runner: fixture.runner, preparation: preparation, factory: { _, _, files in
                    trace.record(files)
                    throw FlutterAndroidWorkflow.failure()
                })
        }
        #expect(trace.count == 1)
        #expect(fixture.runner.log.all.dropFirst(observed).isEmpty)
        #expect(fixture.runner.log.spawned.isEmpty)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("doctor's first model uses the prepared private view")
    func doctorUsesView() async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        _ = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner,
            flutterFactory: fixture.factory(trace))
        let gradle = fixture.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(trace.count == 1)
        #expect(!gradle.isEmpty)
        #expect(gradle.allSatisfy { $0.environment["RUNSTIR_FIXTURE_VIEW"] == "same-view"
            && $0.environment["FLUTTER_ROOT"] == fixture.view.path })
        #expect(!fixture.runner.log.all.contains { $0.arguments.contains("install") || $0.executable.hasSuffix("/bin/flutter") })
    }

    @Test("GUI inspection retains Flutter Android choices in one protected view without starting the app", arguments: [false, true])
    func inspectedTargets(_ workspace: Bool) async throws {
        let fixture = try RuntimeFixture(workspace: workspace)
        let trace = Trace()
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let source = fixture.app.appendingPathComponent("lib/main.dart")
        let before = try Data(contentsOf: source)
        let result = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner,
            includeTargets: true, flutterFactory: { _, _, files in trace.record(files); return View(sdk: sdk) })
        #expect(result.targets?.modules == [":app"])
        #expect(result.targets?.variants == ["debug"])
        #expect(result.targets?.devices.map(\.id) == ["avd:Pixel"])
        let commands = fixture.runner.base.log.all
        let metadata = commands.filter { $0.executable == "./gradlew" }
        #expect(trace.count == 1)
        #expect(!metadata.isEmpty)
        #expect(metadata.allSatisfy { $0.environment["RUNSTIR_FIXTURE_VIEW"] == "same-view"
            && $0.environment["FLUTTER_ROOT"] == sdk.path && $0.arguments.contains("--offline") })
        #expect(!commands.contains { $0.arguments.contains { $0.contains("assemble") || $0.contains("install") }
            || $0.arguments.contains("launch") || $0.arguments.contains("boot") || $0.executable == "emulator" && !$0.arguments.contains("-list-avds") && !$0.arguments.contains("-accel-check") })
        #expect(fixture.runner.base.log.spawned.isEmpty)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("setup's first model uses the same ready-only protected composition")
    func preparationUsesView() async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        _ = try await PreparationExecution.inspect(fixture.input, runner: fixture.runner,
            flutterFactory: fixture.factory(trace))
        let gradle = fixture.runner.log.all.filter { $0.executable == "./gradlew" }
        #expect(trace.count == 1)
        #expect(!gradle.isEmpty)
        #expect(gradle.allSatisfy { $0.environment["RUNSTIR_FIXTURE_VIEW"] == "same-view" })
    }

    @Test("missing app inputs block doctor, setup and build before the view factory or Gradle", arguments: ["doctor", "setup", "build"])
    func missingInput(_ caller: String) async throws {
        let fixture = try CallerFixture()
        try FileManager.default.removeItem(at: fixture.flutter.repo.url("lib/main.dart"))
        let trace = Trace()
        switch caller {
        case "doctor":
            let result = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner,
                flutterFactory: fixture.factory(trace))
            #expect(result.exitCode != 0)
        case "setup":
            _ = try await PreparationExecution.inspect(fixture.input, runner: fixture.runner,
                flutterFactory: fixture.factory(trace))
        default:
            let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: fixture.factory(trace))
            #expect(result.exitCode != 0)
        }
        #expect(trace.count == 0)
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
        #expect(!FileManager.default.fileExists(atPath: fixture.flutter.repo.url("managed").path))
    }

    @Test("unverified real factory remains blocked in doctor without Gradle or SDK mutation")
    func unsupportedSDK() async throws {
        let fixture = try CallerFixture()
        let sourceSDK = try Self.physical(fixture.flutter.repo.url("sdk"))
        let before = try FlutterAndroidExecution.tree(sourceSDK, bindIdentity: true)
        let result = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner)
        #expect(result.report.checks.contains { $0.id == "android.flutter.execution" && $0.status == .error })
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
        #expect(try FlutterAndroidExecution.tree(sourceSDK, bindIdentity: true) == before)
    }

    @Test("down never requires Flutter preparation or creates an SDK view")
    func downNeedsNoSDK() async throws {
        let fixture = try CallerFixture()
        try FileManager.default.removeItem(at: fixture.flutter.repo.url("sdk"))
        let trace = Trace()
        _ = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: fixture.factory(trace))
        #expect(trace.count == 0)
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew"
            || $0.executable == "curl" || $0.arguments.contains("workspace") })
    }

    @Test("a missed Flutter composition fails closed instead of using the host Gradle runner")
    func missingProtectedHook() async throws {
        let fixture = try CallerFixture()
        let context = await WorkflowContext.make(input: fixture.input, platform: .android,
            anchor: fixture.anchor, runner: fixture.runner)
        #expect(context.androidContext == nil)
        let report = await context.engine.run()
        #expect(report.checks.contains { $0.id == "android.flutter.execution" && $0.status == .error })
        await #expect(throws: DomainError.self) {
            try await context.projectRunner.run(ProcessCommand("./gradlew", ["help"], workingDirectory: fixture.flutter.repo.url("android")))
        }
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
    }

    @Test("workspace member uses the root config and lock through existing PreparedInputs")
    func workspaceMember() async throws {
        let fixture = try CallerFixture()
        let repo = fixture.flutter.repo
        try repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: ^3.6.0\nworkspace:\n  - apps/client\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.write("apps/client/pubspec.yaml", "name: client\nresolution: workspace\nenvironment:\n  sdk: ^3.6.0\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.write("apps/client/lib/main.dart", "void main() {}\n")
        try repo.write("apps/client/android/local.properties", "flutter.sdk=\(repo.url("sdk").path)\n")
        try repo.write("apps/client/android/settings.gradle", "include ':app'\n")
        let app = repo.url("apps/client")
        let config = try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": [
            ["name": "example", "rootUri": repo.root.absoluteString],
            ["name": "client", "rootUri": app.absoluteString],
            ["name": "flutter", "rootUri": repo.url("sdk/packages/flutter").absoluteString]
        ]])
        let graph = try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example", "client"], "packages": [
            ["name": "example", "dependencies": ["flutter"], "devDependencies": []],
            ["name": "client", "dependencies": ["flutter"], "devDependencies": []],
            ["name": "flutter", "dependencies": [], "devDependencies": []]
        ]])
        try config.write(to: repo.url(".dart_tool/package_config.json"))
        try graph.write(to: repo.url(".dart_tool/package_graph.json"))
        var runner = fixture.runner
        runner.responses[fixture.flutter.workspaceCommand] = .ok("{\"packages\":[{\"path\":\"\(repo.root.path)\"},{\"path\":\"\(app.path)\"}]}")
        let preparation = try await FlutterPreparation.inspect(directory: app, environment: fixture.input.environment,
            runner: runner, installationRoot: repo.url("managed"))
        let input = ProjectInspectionInput(directory: app, environment: fixture.input.environment, platform: .android)
        let candidate = try #require(input.selection().selected)
        let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
        let trace = Trace()
        _ = try await FlutterAndroidWorkflow.make(input: input, anchor: anchor, runner: runner,
            preparation: preparation, tools: fixture.tools, factory: fixture.factory(trace))
        #expect(trace.count == 1)
        #expect(trace.tracked.contains(try Self.physical(repo.url("pubspec.lock")).path))
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent(".dart_tool/package_config.json").path))
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("pubspec.lock").path))
    }

    @Test("cancellation after the factory returns retains the view and starts no Gradle")
    func cancelledAfterView() async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        let factory = fixture.factory(trace)
        let events = Mutable<[WorkflowEvent]>([])
        let eventsBeforeView = Mutable<[WorkflowEvent]>([])
        let task = Task {
            await WorkflowExecution.run(.build, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: { app, preparation, files in
                    eventsBeforeView.value = events.value
                    let view = try factory(app, preparation, files)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return view
                }, onEvent: { event in events.mutate { $0.append(event) } })
        }
        let result = await task.value
        // The long view preparation is visible before any stage reports.
        #expect(eventsBeforeView.value.map(\.kind) == ["started", "detail"])
        #expect(eventsBeforeView.value.last?.detail == FlutterAndroidWorkflow.preparingViewDetail)
        #expect(result.operation.state == "cancelled")
        #expect(result.exitCode == 130)
        #expect(trace.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.view.path))
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
    }

    @Test("doctor and setup report the SDK view preparation before the factory runs", arguments: ["doctor", "setup"])
    func viewPreparationReported(_ caller: String) async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        let factory = fixture.factory(trace)
        let reported = Mutable<[String]>([])
        let reportedBeforeView = Mutable<[String]>([])
        let wrapped: FlutterAndroidWorkflow.Factory = { app, preparation, files in
            reportedBeforeView.value = reported.value
            return try factory(app, preparation, files)
        }
        if caller == "doctor" {
            _ = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner,
                flutterFactory: wrapped) { detail in reported.mutate { $0.append(detail) } }
        } else {
            _ = await PreparationExecution.run(input: fixture.input, planOnly: true, runner: fixture.runner,
                leases: fixture.leases, flutterFactory: wrapped) { event in
                    if event.kind == "detail", let detail = event.detail { reported.mutate { $0.append(detail) } }
                }
        }
        #expect(trace.count >= 1)
        #expect(reportedBeforeView.value.last == FlutterAndroidWorkflow.preparingViewDetail)
        #expect(reported.value.last == FlutterAndroidWorkflow.viewReadyDetail)
    }

    @Test("RN and native Android callers never enter the Flutter factory", arguments: ["rn", "native"])
    func otherFrameworks(_ kind: String) async throws {
        let repo = try FixtureRepo()
        let trace = Trace()
        let factory: FlutterAndroidWorkflow.Factory = { _, _, files in
            trace.record(files)
            throw FlutterAndroidWorkflow.failure()
        }
        if kind == "rn" {
            try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
            try repo.directory("ios")
            let runner = FakeProcessRunner(responses: ["xcode-select -p": .failed(1, "fixture"),
                "npm config get cache": .ok(repo.root.path), "node --version": .ok("v22.11.0")])
            let result = try await EnvironmentInspection.run(input: ProjectInspectionInput(directory: repo.root,
                environment: [:], platform: .ios), runner: runner, flutterFactory: factory)
            #expect(!result.report.checks.contains { $0.id == "android.flutter.execution" })
        } else {
            try repo.write("settings.gradle", "include ':app'\n")
            try repo.write("app/build.gradle", "plugins { id 'com.android.application' }\n")
            try repo.write("gradlew", "fixture")
            let input = ProjectInspectionInput(directory: repo.root, environment: [:], platform: .android)
            let candidate = try #require(input.selection().selected)
            let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
            #expect(anchor.framework == .nativeAndroid)
            _ = await WorkflowExecution.run(.down, input: WorkflowInput(project: input), runner: FakeProcessRunner(),
                leases: ResourceLeases(directory: repo.url("leases")), flutterFactory: factory)
        }
        #expect(trace.count == 0)
    }

    @Test("unexpected factory errors retain tool-failure classification", arguments: ["doctor", "setup", "build"])
    func factoryToolFailure(_ caller: String) async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        let factory: FlutterAndroidWorkflow.Factory = { _, _, files in
            trace.record(files)
            throw FixtureMiss(command: "owned fixture factory failure")
        }
        switch caller {
        case "doctor":
            let result = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner, flutterFactory: factory)
            #expect(result.exitCode == 2)
            #expect(result.report.hasToolFailure)
        case "setup":
            await #expect(throws: FixtureMiss.self) {
                try await PreparationExecution.inspect(fixture.input, runner: fixture.runner, flutterFactory: factory)
            }
        default:
            let result = await WorkflowExecution.run(.build, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
            #expect(result.exitCode == 2)
        }
        #expect(trace.count == 1)
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
    }

    @Test("iOS composition never enters the Android view factory")
    func iosRoute() async throws {
        let fixture = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: fixture)
        let trace = Trace()
        let result = await WorkflowExecution.run(.build, input: fixture.input(), runner: runner,
            leases: fixture.leases, flutterFactory: { _, _, files in
                trace.record(files)
                throw FlutterAndroidWorkflow.failure()
            })
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(trace.count == 0)
    }

    @Test("invalid Android iOS selectors and build/down ports stop before the factory", arguments: ["scheme", "configuration", "build-port", "down-port"])
    func earlySelectors(_ selector: String) async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        if selector.hasSuffix("-port") {
            let result = await WorkflowExecution.run(selector == "build-port" ? .build : .down,
                input: WorkflowInput(project: fixture.input, port: 8097),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: fixture.factory(trace))
            #expect(result.exitCode == 1)
        } else {
            let result = try await EnvironmentInspection.run(input: fixture.input, runner: fixture.runner,
                scheme: selector == "scheme" ? "Runner" : nil,
                configuration: selector == "configuration" ? "Debug" : nil, flutterFactory: fixture.factory(trace))
            #expect(result.exitCode == 1)
        }
        #expect(trace.count == 0)
        #expect(fixture.runner.log.all.isEmpty)
    }

    @Test("invalid Flutter Android up ports stop before tools or the factory", arguments: [-1, 0, 65536])
    func invalidPort(_ port: Int) async throws {
        let fixture = try CallerFixture()
        let trace = Trace()
        let input = WorkflowInput(project: fixture.input, port: port)
        let result = await WorkflowExecution.run(.up, input: input, runner: fixture.runner, leases: fixture.leases)
        #expect(result.exitCode == 1)
        let injected = await WorkflowExecution.run(.up, input: input, runner: fixture.runner,
            leases: fixture.leases, flutterFactory: fixture.factory(trace))
        #expect(injected.exitCode == 1)
        #expect(trace.count == 0)
        #expect(fixture.runner.log.all.isEmpty)
    }

    @Test("shared Android up forwards its selected or automatic leased port and entrypoint; down creates no view", arguments: [false, true], [false, true])
    func sharedRuntime(_ workspace: Bool, _ explicitPort: Bool) async throws {
        let fixture = try RuntimeFixture(workspace: workspace)
        let trace = Trace()
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, files in trace.record(files); return View(sdk: sdk) }
        let requested = explicitPort ? try FlutterIOSWorkflow.availablePort(nil) : nil
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input, port: requested),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? result.operation.nextAction ?? ""))
        let selected = try #require(result.operation.selection?.selected)
        let appIdentity = try FolderIdentity(directory: fixture.app)
        let workspaceIdentity = try FolderIdentity(directory: fixture.native.repo.root)
        #expect(selected.app == appIdentity)
        #expect(selected.workspace == workspaceIdentity)
        let port = try #require(result.operation.port)
        #expect((1...65535).contains(port))
        if let requested { #expect(port == requested) }
        #expect(fixture.runner.forwardedPort == port)
        #expect(result.up?.context.androidProduct?.flutterConnection?.hostPort == port)
        #expect(fixture.runner.portLeaseHeld)
        let owner = try #require(fixture.runner.folderOwner)
        #expect(try FolderIdentity(directory: URL(fileURLWithPath: owner)) == FolderIdentity(directory: fixture.app))
        if workspace { #expect(try FolderIdentity(directory: URL(fileURLWithPath: owner)) != FolderIdentity(directory: fixture.native.repo.root)) }
        let record = try #require(try AndroidActiveRunStore(project: fixture.app).read())
        let target = try #require(record.target.entrypoint)
        #expect(try Self.physical(URL(fileURLWithPath: target)).path == Self.physical(fixture.app.appendingPathComponent("lib/main.dart")).path)
        let reportedTarget = try #require(result.operation.entrypoint)
        #expect(try Self.physical(URL(fileURLWithPath: reportedTarget)).path == Self.physical(URL(fileURLWithPath: target)).path)
        #expect(trace.count == 1)
        // Like iOS, the authenticated URI is public exactly once, as the development service URI (ADR-0044).
        #expect(result.operation.developmentServiceURI == "http://127.0.0.1:\(port)/sentinel-secret=/")
        #expect(try result.encoded(toolVersion: "fixture").components(separatedBy: "sentinel-secret").count == 2)
        #expect(!(result.up?.stages ?? []).contains { $0.detail?.contains("sentinel-secret") == true })
        try FileManager.default.removeItem(at: fixture.native.repo.url("flutter-sdk"))
        if workspace {
            let manifest = fixture.native.repo.url("pubspec.yaml")
            let originalManifest = try Data(contentsOf: manifest)
            try "name: example\nenvironment:\n  sdk: ^3.6.0\n".write(to: manifest, atomically: false, encoding: .utf8)
            let beforeUnknown = fixture.runner.base.log.all.count
            let unknown = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases)
            #expect(unknown.exitCode == 1)
            #expect(fixture.runner.base.log.all.count == beforeUnknown)
            #expect(try AndroidActiveRunStore(project: fixture.app).read() == record)
            try originalManifest.write(to: manifest)
            let key = ResourceKey.folder(try FolderIdentity(directory: fixture.native.repo.root))
            let other = LeaseOwner(operationId: "workspace-setup", command: "setup", project: fixture.native.repo.root.path)
            let folder = try fixture.leases.acquire([key], owner: other)
            let beforeFolder = fixture.runner.base.log.all.count
            let blockedFolder = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases)
            #expect(blockedFolder.exitCode == 1)
            #expect(blockedFolder.operation.conflict?.key == key)
            #expect(blockedFolder.operation.conflict?.owner == other)
            #expect(fixture.runner.base.log.all.count == beforeFolder)
            #expect(try AndroidActiveRunStore(project: fixture.app).read() == record)
            folder.release()
        }
        let occupied = try fixture.leases.acquire([.port(port)], owner: LeaseOwner(
            operationId: "other-server", command: "fixture", project: "/other-app"))
        let beforeDown = fixture.runner.base.log.all.count
        let blocked = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases)
        #expect(blocked.exitCode == 1)
        #expect(blocked.operation.conflict?.key == .port(port))
        #expect(fixture.runner.base.log.all.count == beforeDown)
        #expect(try AndroidActiveRunStore(project: fixture.app).read() == record)
        occupied.release()
        let down = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(down.exitCode == 0, Comment(rawValue: down.down?.toolFailures.joined(separator: "; ") ?? ""))
        #expect(trace.count == 1)
        #expect(try AndroidActiveRunStore(project: fixture.app).read() == nil)
        #expect(fixture.runner.base.log.spawned.isEmpty)
    }

    @Test("explicit Flutter manual dependencies reach the protected Android workflow", arguments: [WorkflowKind.build, .up])
    func manuallyPreparedDependencies(_ kind: WorkflowKind) async throws {
        let fixture = try RuntimeFixture(workspace: true)
        let trace = Trace()
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, preparation, files in
            #expect(preparation.preparedDependencies)
            trace.record(files)
            return View(sdk: sdk)
        }
        let result = await WorkflowExecution.run(kind,
            input: WorkflowInput(project: fixture.input, preparedDependencies: true),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.preparedDependencies == true)
        #expect(result.up?.stages.first { $0.id == "dependencies" }?.status == .skipped)
        #expect(trace.count == 1)
        #expect(!fixture.runner.base.log.all.contains { $0.arguments.contains("get") || $0.executable.hasSuffix("/bin/flutter") })
        if kind == .up {
            #expect(result.operation.developmentServiceURI != nil)
            let down = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
            #expect(down.exitCode == 0)
            #expect(try AndroidActiveRunStore(project: fixture.app).read() == nil)
        }
        #expect(trace.count == 1)
    }

    @Test("a record left at the pre-folder location blocks up but down leases its forward port and cleans it")
    func legacyRecordDown() async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0, Comment(rawValue: first.up?.failure?.message ?? first.operation.nextAction ?? ""))
        let port = try #require(first.operation.port)
        let current = try AndroidActiveRunStore(project: fixture.app).file
        let legacy = RunLogs(project: fixture.app).directory.appendingPathComponent(AndroidActiveRunStore.fileName)
        try FileManager.default.moveItem(at: current, to: legacy)
        let record = try Data(contentsOf: legacy)
        let downStore = AndroidActiveRunStore(project: fixture.app, operation: .down)

        let beforeUp = fixture.runner.base.log.all.count
        let up = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(up.exitCode != 0)
        #expect(!fixture.runner.base.log.all.dropFirst(beforeUp).contains { $0.arguments.contains("install") })
        #expect(try Data(contentsOf: legacy) == record)

        let occupied = try fixture.leases.acquire([.port(port)], owner: LeaseOwner(
            operationId: "other-server", command: "fixture", project: "/other-app"))
        let blocked = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases)
        #expect(blocked.exitCode == 1)
        #expect(blocked.operation.conflict?.key == .port(port))
        #expect(try Data(contentsOf: legacy) == record)
        occupied.release()

        let down = await WorkflowExecution.run(.down, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases)
        #expect(down.exitCode == 0, Comment(rawValue: down.down?.toolFailures.joined(separator: "; ") ?? ""))
        #expect(try downStore.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("physical and system-alias inventory roots retain the same protected inputs and refuse source links")
    func inventoryRootIdentity() async throws {
        let fixture = try CallerFixture()
        let repo = fixture.flutter.repo
        try repo.write("lib/build/source.dart", "preserved source\n")
        try repo.write("build/generated.txt", "generated\n")
        let physical = try Self.physical(repo.root)
        let system = ["/private/tmp", "/private/var", "/private/etc"].first { physical.path.hasPrefix($0 + "/") }
        try #require(system != nil)
        let alias = URL(fileURLWithPath: String(physical.path.dropFirst("/private".count)), isDirectory: true)
        #expect(try FolderIdentity(directory: physical) == FolderIdentity(directory: alias))
        let preparation = try await fixture.flutter.inspect(fixture.runner)
        var observations: [Set<String>] = []
        var guards: [FlutterAndroidExecution.PreparedInputs] = []
        for root in [physical, alias] {
            let files = try PreparationExecution.sourceFiles(root, packageRoots: [root])
            observations.append(Set(try files.keys.map { try Self.physical(URL(fileURLWithPath: $0)).path }))
            #expect(files.keys.contains { URL(fileURLWithPath: $0).lastPathComponent == "source.dart" })
            #expect(!files.keys.contains { URL(fileURLWithPath: $0).lastPathComponent == "generated.txt" })
            let inputs = try FlutterAndroidExecution.preparedInputs(app: physical, preparation: preparation,
                trackedFiles: files.keys.map { URL(fileURLWithPath: $0) })
            try inputs.check()
            guards.append(inputs)
        }
        #expect(observations[0] == observations[1])
        try repo.write("lib/build/source.dart", "external change\n")
        for inputs in guards { #expect(throws: DomainError.self) { try inputs.check() } }
        let outside = try FixtureRepo()
        try outside.write("other.dart", "preserved outside source\n")
        #expect(throws: (any Error).self) {
            try PreparationExecution.sourceFiles(physical, packageRoots: [outside.root])
        }
        try FileManager.default.createSymbolicLink(at: repo.url("lib/alias.dart"), withDestinationURL: outside.url("other.dart"))
        let files = try PreparationExecution.sourceFiles(alias, packageRoots: [alias])
        #expect(files.contains { URL(fileURLWithPath: $0.key).lastPathComponent == "alias.dart" && $0.value.hasPrefix("symlink:") })
        #expect(throws: DomainError.self) {
            try FlutterAndroidExecution.preparedInputs(app: physical, preparation: preparation,
                trackedFiles: files.keys.map { URL(fileURLWithPath: $0) })
        }
        #expect(try String(contentsOf: outside.url("other.dart"), encoding: .utf8) == "preserved outside source\n")
        withExtendedLifetime(outside) {}
    }

    @Test("another owner of a selected Android port blocks changes before install, launch or forward")
    func selectedPortConflict() async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let port = try FlutterIOSWorkflow.availablePort(nil)
        let other = LeaseOwner(operationId: "other-server", command: "fixture", project: "/other-app")
        let occupied = try fixture.leases.acquire([.port(port)], owner: other)
        defer { occupied.release() }
        let trace = Trace()
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input, port: port),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: { _, _, files in
                trace.record(files); return View(sdk: sdk)
            })
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.key == .port(port), Comment(rawValue: result.up?.failure?.message ?? result.operation.nextAction ?? ""))
        #expect(result.operation.conflict?.owner == other)
        #expect(trace.count == 1)
        #expect(!fixture.runner.base.log.all.contains { $0.arguments.contains("install")
            || $0.arguments.contains("force-stop") || $0.arguments.contains("--no-rebind")
            || $0.arguments.contains { $0.hasPrefix(":app:assemble") } })
        #expect(fixture.runner.base.log.spawned.isEmpty)
        #expect(try AndroidActiveRunStore(project: fixture.app).read() == nil)
    }

    @Test("repeated up installs the new APK and replaces only its verified forward under the old port lease")
    func repeatedUp() async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0)
        let store = AndroidActiveRunStore(project: fixture.app)
        let old = try #require(try store.read())
        let apk = try #require(first.up?.context.androidProduct?.apkPath)
        let freshBytes = Data("newly assembled APK fixture".utf8)
        try freshBytes.write(to: URL(fileURLWithPath: apk))
        let before = fixture.runner.base.log.all.count
        let second = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(second.exitCode == 0, Comment(rawValue: second.up?.failure?.message ?? second.operation.nextAction ?? ""))
        let current = try #require(try store.read())
        #expect(second.operation.port == old.forward?.hostPort)
        #expect(current.device == old.device)
        #expect(current.forward?.state == .created)
        #expect(current.forward?.operationID != old.forward?.operationID)
        #expect(current.app?.pid != old.app?.pid)
        #expect(fixture.runner.installedArtifacts.last == freshBytes)
        #expect(fixture.runner.retiredPortLeaseHeld)
        let commands = Array(fixture.runner.base.log.all.dropFirst(before))
        let remove = try #require(commands.firstIndex { $0.arguments.contains("--remove") })
        let install = try #require(commands.firstIndex { $0.arguments.contains("install") })
        let launch = try #require(commands.firstIndex { $0.arguments.contains("start") })
        #expect(remove < install && install < launch)
        #expect(commands.filter { $0.arguments.contains("--remove") }.count == 1)
        #expect(!commands.contains { $0.arguments.contains("kill") || $0.arguments.contains("uninstall") })
    }

    @Test("omitted port re-entry takes the recorded common port lease before any new build or app change")
    func recordedPortConflict() async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0)
        let store = AndroidActiveRunStore(project: fixture.app)
        let old = try #require(try store.read())
        let port = try #require(old.forward?.hostPort)
        let owner = LeaseOwner(operationId: "other-port", command: "fixture", project: "/other-app")
        let held = try fixture.leases.acquire([.port(port)], owner: owner)
        defer { held.release() }
        let before = fixture.runner.base.log.all.count
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.key == .port(port))
        #expect(result.operation.conflict?.owner == owner)
        #expect(try store.read() == old)
        #expect(!fixture.runner.base.log.all.dropFirst(before).contains { $0.arguments.contains("install")
            || $0.arguments.contains("force-stop") || $0.arguments.contains("--remove")
            || $0.arguments.contains { $0.hasPrefix(":app:assemble") } })
    }

    @Test("unretired foreign, changed, pending and cancelled runs preserve the old app, device and forward", arguments: ["mapping", "pid", "target", "record", "pending", "cancel"])
    func rejectedReentry(_ fault: String) async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0)
        let store = AndroidActiveRunStore(project: fixture.app)
        let old = try #require(try store.read())
        var expected = old
        if fault == "target" {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
            var target = try #require(object["target"] as? [String: Any])
            var forward = try #require(object["forward"] as? [String: Any])
            target["variant"] = "release"; forward["variant"] = "release"
            object["target"] = target; object["forward"] = forward
            expected = try JSONDecoder().decode(AndroidActiveRun.self, from: JSONSerialization.data(withJSONObject: object))
            try store.write(expected)
        }
        if fault == "mapping" { fixture.runner.forwardSerial = "emulator-5556" }
        if fault == "pid" { fixture.runner.pidOverride = 9999 }
        if fault == "pending" {
            var pending = old
            pending.forward?.state = .pending
            try store.write(pending)
        }
        if fault == "record" {
            fixture.runner.beforeForwardList = {
                var changed = try #require(try store.read())
                changed.forward?.state = .pending
                try store.write(changed)
            }
        }
        if fault == "cancel" { fixture.runner.beforeForwardList = { throw CancellationError() } }
        let before = fixture.runner.base.log.all.count
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == (fault == "cancel" ? 130 : fault == "pending" || fault == "target" ? 1 : 2))
        let current = try #require(try store.read())
        #expect(current.device == old.device && current.app == old.app)
        if fault == "record" || fault == "pending" { #expect(current.forward?.state == .pending) }
        else { #expect(current == expected) }
        #expect(!fixture.runner.base.log.all.dropFirst(before).contains { $0.arguments.contains("install")
            || $0.arguments.contains("force-stop") || $0.arguments.contains("--remove") || $0.arguments.contains("kill") })
    }

    @Test("confirmed retirement whose ledger commit fails starts no install, launch or old-resource cleanup", arguments: [false, true])
    func retirementCommitFailure(symbolicLink: Bool) async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0)
        let store = AndroidActiveRunStore(project: fixture.app)
        let old = try #require(try store.read())
        let backup = fixture.native.repo.url("old-forward.json")
        let foreign = fixture.native.repo.url("foreign.txt")
        try Data("foreign record".utf8).write(to: foreign)
        fixture.runner.afterForwardRemoval = {
            try FileManager.default.moveItem(at: store.file, to: backup)
            if symbolicLink { try FileManager.default.createSymbolicLink(at: store.file, withDestinationURL: foreign) }
            else {
                var changed = old
                changed.forward?.state = .pending
                try store.write(changed)
            }
        }
        let before = fixture.runner.base.log.all.count
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == (symbolicLink ? 1 : 2))
        #expect(try JSONDecoder().decode(AndroidActiveRun.self, from: Data(contentsOf: backup)) == old)
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "foreign record")
        if symbolicLink { #expect(throws: DomainError.self) { _ = try store.read() } }
        else { #expect(try store.read()?.forward?.state == .pending) }
        let commands = Array(fixture.runner.base.log.all.dropFirst(before))
        #expect(commands.filter { $0.arguments.contains("--remove") }.count == 1)
        #expect(!commands.contains { $0.arguments.contains("install") || $0.arguments.contains("force-stop") || $0.arguments.contains("kill") })
    }

    @Test("a failed new service rolls back only its new app and preserves an earlier started device record")
    func reentryRollbackScope() async throws {
        let fixture = try RuntimeFixture(workspace: false)
        let sdk = try fixture.native.repo.directory("owned-sdk-view")
        let factory: FlutterAndroidWorkflow.Factory = { _, _, _ in View(sdk: sdk) }
        let first = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(first.exitCode == 0)
        let store = AndroidActiveRunStore(project: fixture.app)
        var old = try #require(try store.read())
        old.device?.state = .started
        old.device?.launcherPID = 7777
        try store.write(old)
        fixture.runner.failFreshService = true
        let before = fixture.runner.base.log.all.count
        let result = await WorkflowExecution.run(.up, input: WorkflowInput(project: fixture.input),
            runner: fixture.runner, leases: fixture.leases, flutterFactory: factory)
        #expect(result.exitCode == 2)
        let remaining = try #require(try store.read())
        #expect(remaining.device == old.device)
        #expect(remaining.app == nil && remaining.forward == nil)
        #expect(result.up?.context.androidProduct?.rollback?.map(\.id) == ["android.adb.forward", "android.app"])
        #expect(!fixture.runner.base.log.all.dropFirst(before).contains { $0.arguments.contains("kill") })
    }

    @Test("common source inventory protects nested generated-looking source and log assets", arguments: [false, true])
    func protectedInventory(_ namedBuildPackage: Bool) async throws {
        let fixture = try CallerFixture()
        let repo = fixture.flutter.repo
        var runner = fixture.runner
        var sources = ["lib/build/feature.dart", "lib/vendor/feature.dart", "assets/reference.log"]
        if namedBuildPackage {
            try repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: ^3.6.0\nworkspace:\n  - build\ndependencies:\n  flutter:\n    sdk: flutter\n")
            try repo.write("build/pubspec.yaml", "name: build\nresolution: workspace\nenvironment:\n  sdk: ^3.6.0\ndependencies:\n  flutter:\n    sdk: flutter\n")
            sources.append("build/lib/package.dart")
            let packages = [("example", repo.root), ("build", repo.url("build")), ("flutter", repo.url("sdk/packages/flutter"))]
            try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }])
                .write(to: repo.url(".dart_tool/package_config.json"))
            try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example", "build"], "packages": packages.map {
                ["name": $0.0, "dependencies": $0.0 == "flutter" ? [] : ["flutter"], "devDependencies": []] as [String: Any]
            }]).write(to: repo.url(".dart_tool/package_graph.json"))
            runner.responses[fixture.flutter.workspaceCommand] = .ok(
                String(decoding: try JSONSerialization.data(withJSONObject: ["packages": [repo.root, repo.url("build")].map { ["path": $0.path] }]), as: UTF8.self))
        }
        for source in sources { try repo.write(source, "preserved source\n") }
        let outputs = [namedBuildPackage ? "build/build/generated.txt" : "build/generated.txt",
                       ".dart_tool/flutter_build/cache.bin", "android/.gradle/cache.bin"]
        for output in outputs { try repo.write(output, "old generated bytes\n") }
        let preparation = try await fixture.flutter.inspect(runner)
        let trace = Trace()
        _ = try await FlutterAndroidWorkflow.make(input: fixture.input, anchor: fixture.anchor,
            runner: runner, preparation: preparation, tools: fixture.tools, factory: fixture.factory(trace))
        for source in sources { #expect(trace.tracked.contains(try Self.physical(repo.url(source)).path)) }
        for output in outputs { #expect(!trace.tracked.contains(try Self.physical(repo.url(output)).path)) }
        let tracked = trace.tracked.map { URL(fileURLWithPath: $0) }
        let prepared = try FlutterAndroidExecution.preparedInputs(app: repo.root, preparation: preparation, trackedFiles: tracked)
        let privateRoot = try FlutterAndroidExecution.makeRoot(in: Self.physical(repo.root))
        let policy = privateRoot.appendingPathComponent("parent.sb")
        let text = try FlutterAndroidExecution.parentPolicy(protected: Array(prepared.files.keys) + Array(prepared.absent),
            privateRoot: privateRoot, writable: [])
        try FlutterAndroidExecution.write(Data(text.utf8), to: policy)
        let child = SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], workingDirectory: privateRoot)
        for source in sources {
            let file = try Self.physical(repo.url(source))
            let before = try FlutterAndroidExecution.entry(file, bindIdentity: true)
            for script in ["printf changed > \"$1\"", "/bin/rm \"$1\""] {
                let command = ProcessCommand("/bin/sh", ["-c", script, "fixture", file.path], workingDirectory: privateRoot)
                let result = try await child.run(FlutterAndroidExecution.policyCommand(command, file: policy))
                #expect(!result.terminationStatus.isSuccess)
                #expect(try FlutterAndroidExecution.entry(file, bindIdentity: true) == before)
            }
        }
        for output in outputs {
            let file = try Self.physical(repo.url(output))
            let command = ProcessCommand("/bin/sh", ["-c", "printf generated > \"$1\"", "fixture", file.path], workingDirectory: privateRoot)
            let result = try await child.run(FlutterAndroidExecution.policyCommand(command, file: policy))
            #expect(result.terminationStatus.isSuccess, Comment(rawValue: result.combinedOutput))
        }
        try prepared.check()
        try "external source change\n".write(to: repo.url(sources[0]), atomically: false, encoding: .utf8)
        #expect(throws: DomainError.self) { try prepared.check() }
    }

    @Test("the final host boundary encloses real mise activation and preserves argument privacy", arguments: [false, true])
    func miseHostBoundary(_ redacted: Bool) async throws {
        let fixture = try CallerFixture()
        let repo = fixture.flutter.repo
        try repo.write("mise.toml", "[tools]\njava = '17.0.12'\n")
        let policy = try Self.physical(repo.root).appendingPathComponent("parent.sb")
        try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: policy)
        let sourceFile = repo.url("lib/main.dart")
        let originalSDKRoot = try Self.physical(repo.url("sdk"))
        let source = try Data(contentsOf: sourceFile)
        let originalSDK = try FlutterAndroidExecution.tree(originalSDKRoot, bindIdentity: true)
        let trace = GuardTrace()
        let git = ProcessCommand("git", ["-C", repo.root.path, "ls-files", "--error-unmatch", "--", "mise.toml"])
        let activation = ProcessCommand("mise", ["exec", "--", "true"], workingDirectory: repo.root)
        let original = ProcessCommand("./gradlew", ["--offline", "help"] + (redacted ? ["-PfixtureCredential=sentinel-secret"] : []),
            workingDirectory: repo.url("android"), redactArguments: redacted)
        let mise = ProcessCommand("mise", ["exec", "--", "sh", "-c", "cd \"$1\" && shift && exec \"$@\"",
            "mobile-mise", repo.url("android").path, original.executable] + original.arguments,
            workingDirectory: repo.root, redactArguments: redacted)
        let raw = FakeProcessRunner(responses: [
            try FlutterAndroidExecution.policyCommand(git, file: policy).description: .ok("mise.toml\n"),
            try FlutterAndroidExecution.policyCommand(activation, file: policy).description: .ok(""),
            try FlutterAndroidExecution.policyCommand(mise, file: policy).description: .ok("guarded fixture")
        ])
        let host = FlutterAndroidHostGuard(base: raw, policy: policy, check: {
            try trace.check()
            guard try Data(contentsOf: sourceFile) == source,
                  try FlutterAndroidExecution.tree(originalSDKRoot, bindIdentity: true) == originalSDK else {
                throw FixtureMiss(command: "fixture source or SDK changed")
            }
        }, recordFailure: { trace.record($0, $1) })
        let environment = await ProjectExecutionEnvironment.resolve(anchor: fixture.anchor,
            hostRunner: FlutterChildRunner(base: host, environment: ["FLUTTER_ROOT": fixture.view.path]))
            .activatingTools(fixture.tools.activeTools, environment: fixture.input.environment)
        #expect(try await environment.run().status == .pass)
        let result = try await environment.runner.run(original)
        #expect(result.standardOutput == "guarded fixture")
        #expect(raw.log.all.count == 3)
        #expect(raw.log.all.allSatisfy { $0.executable == "/usr/bin/sandbox-exec"
            && $0.arguments.starts(with: ["-f", policy.path]) && $0.environment["FLUTTER_ROOT"] == fixture.view.path })
        let emitted = try #require(raw.log.all.last)
        #expect(emitted.arguments == ["-f", policy.path] + [mise.executable] + mise.arguments)
        #expect(emitted.arguments.filter { $0 == "/usr/bin/sandbox-exec" }.isEmpty)
        #expect(emitted.redactArguments == redacted)
        if redacted { #expect(!emitted.description.contains("sentinel-secret")) }
        #expect(emitted.environment["MISE_AUTO_INSTALL"] == "false")
        #expect(emitted.environment["JAVA_HOME"] == repo.url("jdk").path)
        let workingDirectory = try #require(emitted.workingDirectory)
        #expect(try Self.physical(workingDirectory).path == Self.physical(repo.root).path)
        #expect(trace.count == 6)
        #expect(trace.failures.isEmpty)
        #expect(raw.log.spawned.isEmpty)
    }

    @Test("direct and already-owned host wrappers preserve true redaction and safe timeout descriptions")
    func directPrivacy() async throws {
        let repo = try FixtureRepo()
        let policy = try Self.physical(repo.root).appendingPathComponent("parent.sb")
        try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: policy)
        let original = ProcessCommand("./gradlew", ["help", "-PfixtureCredential=sentinel-secret"],
            workingDirectory: repo.root, redactArguments: true)
        let wrapped = try FlutterAndroidExecution.policyCommand(original, file: policy)
        #expect(wrapped.redactArguments)
        #expect(wrapped.arguments == ["-f", policy.path, original.executable] + original.arguments)
        #expect(!wrapped.description.contains("sentinel-secret"))
        let raw = FakeProcessRunner(responses: [wrapped.description: .ok("fixture")])
        let trace = GuardTrace()
        let host = FlutterAndroidHostGuard(base: raw, policy: policy,
            check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        _ = try await host.run(original)
        _ = try await host.run(wrapped)
        #expect(raw.log.all.count == 2)
        #expect(raw.log.all.allSatisfy { $0.redactArguments && $0.arguments == wrapped.arguments
            && !$0.description.contains("sentinel-secret") })
        let failure = FakeProcessRunner(failures: [wrapped.description:
            ProcessError.timedOut(command: wrapped.description, timeout: .seconds(1))])
        let failing = FlutterAndroidHostGuard(base: failure, policy: policy,
            check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        do { _ = try await failing.run(original); Issue.record("The fake timeout must escape") }
        catch { #expect(error is ProcessError); #expect(!String(describing: error).contains("sentinel-secret")) }
        #expect(failure.log.all.allSatisfy { $0.redactArguments })
    }

    @Test("only the exact owned parent policy skips an extra host sandbox")
    func exactPolicyOnly() async throws {
        let repo = try FixtureRepo()
        let physicalRoot = try Self.physical(repo.root)
        let policy = physicalRoot.appendingPathComponent("parent.sb")
        let other = physicalRoot.appendingPathComponent("user.sb")
        for file in [policy, other] {
            try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: file)
        }
        let original = ProcessCommand("./gradlew", ["help"], workingDirectory: repo.root)
        let owned = try FlutterAndroidExecution.policyCommand(original, file: policy)
        let user = try FlutterAndroidExecution.policyCommand(original, file: other)
        let nested = try FlutterAndroidExecution.policyCommand(user, file: policy)
        let raw = FakeProcessRunner(responses: [owned.description: .ok("owned"), nested.description: .ok("nested")])
        let trace = GuardTrace()
        let host = FlutterAndroidHostGuard(base: raw, policy: policy, check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        #expect(try await host.run(owned).standardOutput == "owned")
        #expect(try await host.run(user).standardOutput == "nested")
        #expect(raw.log.all.map(\.description) == [owned.description, nested.description])
        #expect(trace.count == 4)
        await #expect(throws: DomainError.self) { try await host.spawnDetached(original, logFile: repo.url("detached.log")) }
        #expect(raw.log.spawned.isEmpty)
    }

    @Test("post-command protection failures preserve primary errors, timeout and cancellation", arguments: ["tool", "timeout", "cancel"])
    func protectionAfterPrimary(_ kind: String) async throws {
        let repo = try FixtureRepo()
        let policy = try Self.physical(repo.root).appendingPathComponent("parent.sb")
        try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: policy)
        let command = ProcessCommand("./gradlew", ["help"], workingDirectory: repo.root)
        let wrapped = try FlutterAndroidExecution.policyCommand(command, file: policy)
        let primary: any Error
        switch kind {
        case "cancel": primary = CancellationError()
        case "timeout": primary = ProcessError.timedOut(command: "fixture child", timeout: .seconds(1))
        default: primary = FixtureMiss(command: "primary fixture failure")
        }
        let raw = FakeProcessRunner(failures: [wrapped.description: primary])
        let trace = GuardTrace(failAt: 2)
        let host = FlutterAndroidHostGuard(base: raw, policy: policy, check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        do {
            _ = try await host.run(command)
            Issue.record("The fake primary failure must escape")
        } catch {
            switch kind {
            case "cancel": #expect(error is CancellationError)
            case "timeout":
                let timeout = try #require(error as? ProcessError)
                guard case .timedOut(let command, let duration) = timeout else {
                    Issue.record("The timeout classification must survive")
                    return
                }
                #expect(command == "fixture child")
                #expect(duration == .seconds(1))
            default: #expect(error is FixtureMiss)
            }
        }
        #expect(trace.count == 2)
        #expect(trace.failures.count == 1)
        #expect(trace.failures.first?.contains("post-command fixture protection") == true)
        #expect(raw.log.all.count == 1)
    }

    @Test("a protection check interrupted by cancellation is not recorded as a protection failure")
    func cancelledProtectionCheck() async throws {
        let repo = try FixtureRepo()
        let policy = try Self.physical(repo.root).appendingPathComponent("parent.sb")
        try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: policy)
        let command = ProcessCommand("./gradlew", ["help"], workingDirectory: repo.root)
        let wrapped = try FlutterAndroidExecution.policyCommand(command, file: policy)
        let raw = FakeProcessRunner(failures: [wrapped.description: CancellationError()])
        let trace = GuardTrace(failAt: 2, failure: CancellationError())
        let host = FlutterAndroidHostGuard(base: raw, policy: policy, check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        await #expect(throws: CancellationError.self) { try await host.run(command) }
        #expect(trace.count == 2)
        #expect(trace.failures.isEmpty)
    }

    @Test("protection receipts are private files outside the private root that cleanup removes")
    func protectionReceiptOutsideRoot() throws {
        let repo = try FixtureRepo()
        let root = try Self.physical(repo.root).appendingPathComponent("runstir-flutter-android-fixture")
        let receipts = repo.url("Library/Logs/dev.runstir/flutter-protection")
        try FlutterAndroidHostGuard.writeReceipt(primary: FixtureMiss(command: "primary fixture failure"),
            protection: FixtureMiss(command: "post-command fixture protection"), root: root, to: receipts)
        let files = try FileManager.default.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil)
        let receipt = try #require(files.first)
        #expect(files.count == 1)
        #expect(receipt.lastPathComponent.hasPrefix("protection-failure-"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any])
        #expect(json["root"] as? String == root.path)
        #expect((json["primary"] as? String)?.contains("primary fixture failure") == true)
        #expect((json["protection"] as? String)?.contains("post-command fixture protection") == true)
        #expect(try FlutterAndroidExecution.entry(receipt).mode == 0o600)
        #expect(try FlutterAndroidExecution.entry(receipts).mode == 0o700)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(FlutterAndroidHostGuard.receiptDirectory.path.hasSuffix("/Library/Logs/dev.runstir/flutter-protection"))
    }

    @Test("input changes before or after a successful child stop execution", arguments: [1, 2])
    func protectionAfterSuccess(_ failingCheck: Int) async throws {
        let repo = try FixtureRepo()
        let policy = try Self.physical(repo.root).appendingPathComponent("parent.sb")
        try FlutterAndroidExecution.write(Data("(version 1)\n(allow default)\n".utf8), to: policy)
        let command = ProcessCommand("./gradlew", ["help"], workingDirectory: repo.root)
        let wrapped = try FlutterAndroidExecution.policyCommand(command, file: policy)
        let raw = FakeProcessRunner(responses: [wrapped.description: .ok("child passed")])
        let trace = GuardTrace(failAt: failingCheck)
        let host = FlutterAndroidHostGuard(base: raw, policy: policy, check: { try trace.check() }, recordFailure: { trace.record($0, $1) })
        await #expect(throws: FixtureMiss.self) { try await host.run(command) }
        #expect(trace.count == failingCheck)
        #expect(trace.failures.isEmpty)
        #expect(raw.log.all.count == failingCheck - 1)
    }

    private static func physical(_ path: URL) throws -> URL {
        guard let resolved = realpath(path.path, nil) else { throw FixtureMiss(command: "fixture realpath") }
        defer { free(resolved) }
        return try FlutterAndroidExecution.canonical(
            URL(fileURLWithPath: String(cString: resolved), isDirectory: path.hasDirectoryPath))
    }

    private final class GuardTrace: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var recorded: [String] = []
        let failAt: Int?
        let failure: any Error
        init(failAt: Int? = nil, failure: any Error = FixtureMiss(command: "post-command fixture protection")) {
            self.failAt = failAt
            self.failure = failure
        }
        func check() throws {
            let count = lock.withLock { calls += 1; return calls }
            if count == failAt { throw failure }
        }
        func record(_ primary: any Error, _ protection: any Error) {
            lock.withLock { recorded.append("\(primary); \(protection)") }
        }
        var count: Int { lock.withLock { calls } }
        var failures: [String] { lock.withLock { recorded } }
    }

    private final class Trace: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var files: [String] = []
        func record(_ values: [URL]) { lock.withLock { calls += 1; files = values.map(\.path) } }
        var count: Int { lock.withLock { calls } }
        var tracked: [String] { lock.withLock { files } }
    }

    /// Reuses the existing native fake model/SDK/APK fixture, never an installed SDK.
    private final class RuntimeFixture {
        let native: NativeAndroidFixture
        let app: URL
        let input: ProjectInspectionInput
        let runner: RuntimeRunner
        var leases: ResourceLeases { native.leases }
        init(workspace: Bool) throws {
            native = try NativeAndroidFixture()
            let repo = native.repo
            let original = try native.runner()
            app = workspace ? try repo.directory("apps/client") : repo.root
            let android = app.appendingPathComponent("android")
            try FileManager.default.copyItem(at: native.project, to: android)
            try "plugins { id(\"com.android.application\") version \"8.13.2\" apply false }\ninclude(\":app\")\n"
                .write(to: android.appendingPathComponent("settings.gradle.kts"), atomically: false, encoding: .utf8)
            try FlutterFixture.sdk(repo: repo, at: "flutter-sdk", version: "3.41.9")
            let manifest = "name: \(workspace ? "client" : "example")\n\(workspace ? "resolution: workspace\n" : "")environment:\n  sdk: ^3.6.0\ndependencies:\n  flutter:\n    sdk: flutter\n"
            try manifest.write(to: app.appendingPathComponent("pubspec.yaml"), atomically: false, encoding: .utf8)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("lib"), withIntermediateDirectories: true)
            try "void main() {}\n".write(to: app.appendingPathComponent("lib/main.dart"), atomically: false, encoding: .utf8)
            if workspace { try repo.write("pubspec.yaml", "name: example\nenvironment:\n  sdk: ^3.6.0\nworkspace:\n  - apps/client\ndependencies:\n  flutter:\n    sdk: flutter\n") }
            try repo.write("pubspec.lock", "packages: {}\n")
            let packages = workspace ? [("example", repo.root), ("client", app), ("flutter", repo.url("flutter-sdk/packages/flutter"))]
                : [("example", app), ("flutter", repo.url("flutter-sdk/packages/flutter"))]
            try repo.directory(".dart_tool")
            try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }])
                .write(to: repo.url(".dart_tool/package_config.json"))
            try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": workspace ? ["example", "client"] : ["example"], "packages": packages.map {
                ["name": $0.0, "dependencies": $0.0 == "flutter" ? [] : ["flutter"], "devDependencies": []] as [String: Any]
            }]).write(to: repo.url(".dart_tool/package_graph.json"))
            try "{\"version\":\"3.41.9\",\"plugins\":{\"ios\":[],\"android\":[]}}"
                .write(to: app.appendingPathComponent(".flutter-plugins-dependencies"), atomically: false, encoding: .utf8)
            try "sdk.dir=\(repo.url("sdk").path)\nflutter.sdk=\(repo.url("flutter-sdk").path)\n"
                .write(to: android.appendingPathComponent("local.properties"), atomically: false, encoding: .utf8)
            var responses: [String: FakeProcessRunner.Response] = [:]
            for (key, response) in original.responses {
                let transformed = key.replacingOccurrences(of: native.project.path, with: android.path)
                let selected = transformed.hasPrefix("adb ") ? transformed.replacingOccurrences(of: "adb ", with: "adb -L tcp:5037 ", options: .anchored) : transformed
                responses[selected] = .init(status: response.status,
                    standardOutput: response.standardOutput.replacingOccurrences(of: native.project.path, with: android.path)
                        + (key.hasPrefix("aapt2 dump badging ") ? "native-code: 'arm64-v8a'\n" : ""),
                    standardError: response.standardError.replacingOccurrences(of: native.project.path, with: android.path))
            }
            let members = workspace ? [repo.root, app] : [app]
            responses[FlutterRelease.command.description] = .ok(
                String(decoding: try FlutterFixture.releaseMetadata(), as: UTF8.self))
            responses[repo.url("flutter-sdk/bin/cache/dart-sdk/bin/dart").path + " pub --suppress-analytics workspace list --json"] = .ok(
                String(decoding: try JSONSerialization.data(withJSONObject: ["packages": members.map { ["path": $0.path] }]), as: UTF8.self))
            var environment = native.input.environment
            environment["FLUTTER_ROOT"] = repo.url("flutter-sdk").path
            input = ProjectInspectionInput(directory: app, environment: environment, platform: .android)
            runner = RuntimeRunner(base: FakeProcessRunner(responses: responses), leases: native.leases,
                folder: try FolderIdentity(directory: repo.root))
        }
        deinit { try? FileManager.default.removeItem(at: RunLogs(project: app).directory) }
    }

    private final class RuntimeRunner: ProcessRunner, @unchecked Sendable {
        let base: FakeProcessRunner
        let leases: ResourceLeases
        let folder: FolderIdentity
        private let lock = NSLock()
        private var mapping: Int?
        private var stopped = false
        private var observedPort: Int?
        private var heldPort = false
        private var observedOwner: String?
        private var launches = 0
        private var installed: [Data] = []
        private var retiredLease = false
        var forwardSerial = "emulator-5554"
        var beforeForwardList: (@Sendable () throws -> Void)?
        var afterForwardRemoval: (@Sendable () throws -> Void)?
        var failFreshService = false
        var pidOverride: Int?
        init(base: FakeProcessRunner, leases: ResourceLeases, folder: FolderIdentity) {
            self.base = base; self.leases = leases; self.folder = folder
        }
        var forwardedPort: Int? { lock.withLock { observedPort } }
        var portLeaseHeld: Bool { lock.withLock { heldPort } }
        var folderOwner: String? { lock.withLock { observedOwner } }
        var installedArtifacts: [Data] { lock.withLock { installed } }
        var retiredPortLeaseHeld: Bool { lock.withLock { retiredLease } }
        func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
            let response: FakeProcessRunner.Response? = try lock.withLock {
                if command.executable == "curl", command.redactArguments,
                   command.arguments.last?.hasPrefix("http://127.0.0.1:\(mapping ?? 0)/sentinel-secret=/") == true {
                    return .ok(#"{"result":{"type":"VM"}}"#)
                }
                guard command.executable == "adb", command.arguments.starts(with: ["-L", "tcp:5037"]) else { return nil }
                let args = Array(command.arguments.dropFirst(2))
                if args == ["forward", "--list"] {
                    let callback = beforeForwardList; beforeForwardList = nil; try callback?()
                    return .ok(mapping.map { "\(forwardSerial) tcp:\($0) tcp:38881\n" } ?? "")
                }
                if args.starts(with: ["-s", "emulator-5554", "forward", "--no-rebind"]), args.count == 6,
                   let port = Int(args[4].dropFirst(4)) {
                    let other = LeaseOwner(operationId: "fixture-other", command: "fixture", project: "/other-app")
                    do { let lease = try leases.acquire([.port(port)], owner: other); lease.release() }
                    catch is ResourceConflict { heldPort = true }
                    do { let lease = try leases.acquire([.folder(folder)], owner: other); lease.release() }
                    catch let conflict as ResourceConflict { observedOwner = conflict.owner?.project }
                    mapping = port; observedPort = port
                    return .ok("")
                }
                if args.starts(with: ["-s", "emulator-5554", "forward", "--remove"]) {
                    if let mapping {
                        do { let lease = try leases.acquire([.port(mapping)], owner: LeaseOwner(
                            operationId: "fixture-retire", command: "fixture", project: "/other-app")); lease.release() }
                        catch is ResourceConflict { retiredLease = true }
                    }
                    mapping = nil
                    let callback = afterForwardRemoval; afterForwardRemoval = nil; try callback?()
                    return .ok("")
                }
                if args.contains("logcat"), args.contains("-t") { return .ok("1792400000.123456 8123 8123 I flutter : marker\n") }
                if args.contains("logcat"), args.contains("-T") {
                    if failFreshService && launches > 1 { return .failed(1, "fixture service failure") }
                    let pid = 8122 + max(1, launches)
                    return .ok("1792400001.123456 \(pid) \(pid) I flutter : The Dart VM service is listening on http://127.0.0.1:38881/sentinel-secret=/\n")
                }
                if args.contains("install"), let path = args.last { installed.append(try Data(contentsOf: URL(fileURLWithPath: path))) }
                if args.contains("force-stop") { stopped = true }
                if args.starts(with: ["-s", "emulator-5554", "shell", "am", "start"]) { stopped = false; launches += 1 }
                if args.contains("pidof"), stopped { return .failed(1, "") }
                if args.contains("pidof") { return .ok("\(pidOverride ?? (8122 + max(1, launches)))\n") }
                return nil
            }
            var selected = base
            if let response { selected.responses[command.description] = response }
            return try await selected.run(command, onLine: onLine)
        }
        func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
            try await base.spawnDetached(command, logFile: logFile)
        }
    }

    private struct View: FlutterAndroidExecutionView {
        let sdk: URL
        func runner(base: any ProcessRunner) -> any ProcessRunner { ViewRunner(base: base) }
    }

    private struct ViewRunner: ProcessRunner {
        let base: any ProcessRunner
        func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
            var selected = command
            if selected.executable == "./gradlew" { selected.environment["RUNSTIR_FIXTURE_VIEW"] = "same-view" }
            return try await base.run(selected, onLine: onLine)
        }
        func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 {
            throw FlutterAndroidWorkflow.failure()
        }
    }

    private struct CallerFixture: @unchecked Sendable {
        let flutter: FlutterFixture
        let runner: FakeProcessRunner
        let view: URL
        let settings: Data
        let anchor: ProjectAnchor
        let input: ProjectInspectionInput
        let tools: ToolPreparation
        var leases: ResourceLeases { ResourceLeases(directory: flutter.repo.url("leases")) }

        init() throws {
            flutter = try FlutterFixture()
            let repo = flutter.repo
            try FileManager.default.removeItem(at: repo.url("ios"))
            try repo.write("android/settings.gradle", "plugins { id 'com.android.application' version '8.13.2' apply false }\ninclude ':app'\n")
            try repo.write("android/gradle.properties", "org.gradle.jvmargs=-Xmx1G\n")
            try repo.write("android/gradle/wrapper/gradle-wrapper.jar", "fixture wrapper jar")
            try repo.write("android/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
            try repo.write("android/gradlew", "fixture; never execute")
            try repo.write("jdk/bin/java", "fixture; never execute")
            try repo.write("home/.gradle/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle", "fixture; never execute")
            try repo.write("home/.gradle/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13-bin.zip.ok", "")
            for path in ["android/gradlew", "jdk/bin/java", "home/.gradle/wrapper/dists/gradle-8.13-bin/hash/gradle-8.13/bin/gradle"] {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repo.url(path).path)
            }
            view = try repo.directory("owned-sdk-view")
            _ = try repo.directory("android-sdk")
            var environment = flutter.environment
            environment["ANDROID_HOME"] = repo.url("android-sdk").path
            input = ProjectInspectionInput(directory: repo.root, environment: environment, platform: .android)
            let candidate = try #require(input.selection().selected)
            anchor = try #require(ProjectAnchor.detect(candidate: candidate))
            settings = try Data(contentsOf: repo.url("android/settings.gradle"))
            let properties = "java.version = 17.0.12\njava.runtime.version = 17.0.12+7\njava.vendor = Eclipse Adoptium\njava.home = \(repo.url("jdk").path)\nos.arch = aarch64\n"
            var selected = flutter.runner()
            selected.responses["java -XshowSettings:properties -version"] = .ok(properties)
            selected.responses["\(repo.url("jdk/bin/java").path) -XshowSettings:properties -version"] = .ok(properties)
            selected.responses["/usr/bin/which java"] = .ok(repo.url("jdk/bin/java").path)
            selected.responses["emulator -accel-check"] = .failed(1, "fixture has no runtime")
            selected.responses["emulator -list-avds"] = .ok("")
            for offline in [false, true] {
                let command = try #require(AndroidGradleModelProbe.command(androidDirectory: repo.url("android"), offline: offline, timeout: nil))
                selected.responses[command.description] = .failed(1, "offline mode: no cached version in fixture")
            }
            selected.responses["./gradlew :app:assembleDebug"] = .ok("fixture build")
            runner = selected
            var prepared = ToolPreparation()
            prepared.checks = [PreparationStep(id: "tools.java", platform: nil, kind: "reuse", target: repo.url("jdk/bin/java").path,
                observed: "fixture existing JDK", required: "existing JDK", source: CheckSource(tier: 1, origin: "fixture"), command: nil, remediation: nil)]
            prepared.activeTools = ["java": repo.url("jdk/bin/java")]
            tools = prepared
        }

        func factory(_ trace: Trace) -> FlutterAndroidWorkflow.Factory {
            let sdk = view
            return { _, _, files in trace.record(files); return View(sdk: sdk) }
        }
    }
}
