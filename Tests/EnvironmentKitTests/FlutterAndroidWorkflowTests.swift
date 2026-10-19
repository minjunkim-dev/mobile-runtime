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
        let task = Task {
            await WorkflowExecution.run(.build, input: WorkflowInput(project: fixture.input),
                runner: fixture.runner, leases: fixture.leases, flutterFactory: { app, preparation, files in
                    let view = try factory(app, preparation, files)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return view
                })
        }
        let result = await task.value
        #expect(result.operation.state == "cancelled")
        #expect(result.exitCode == 130)
        #expect(trace.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.view.path))
        #expect(!fixture.runner.log.all.contains { $0.executable == "./gradlew" })
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

    @Test("the final host boundary encloses real mise activation and the protected Gradle request")
    func miseHostBoundary() async throws {
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
        let original = ProcessCommand("./gradlew", ["--offline", "help"], workingDirectory: repo.url("android"))
        let protected = try FlutterAndroidExecution.policyCommand(original, file: policy)
        let mise = ProcessCommand("mise", ["exec", "--", "sh", "-c", "cd \"$1\" && shift && exec \"$@\"",
            "mobile-mise", repo.url("android").path, protected.executable] + protected.arguments, workingDirectory: repo.root)
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
        let result = try await environment.runner.run(protected)
        #expect(result.standardOutput == "guarded fixture")
        #expect(raw.log.all.count == 3)
        #expect(raw.log.all.allSatisfy { $0.executable == "/usr/bin/sandbox-exec"
            && $0.arguments.starts(with: ["-f", policy.path]) && $0.environment["FLUTTER_ROOT"] == fixture.view.path })
        let emitted = try #require(raw.log.all.last)
        #expect(emitted.arguments == ["-f", policy.path] + [mise.executable] + mise.arguments)
        #expect(emitted.environment["MISE_AUTO_INSTALL"] == "false")
        #expect(emitted.environment["JAVA_HOME"] == repo.url("jdk").path)
        let workingDirectory = try #require(emitted.workingDirectory)
        #expect(try Self.physical(workingDirectory).path == Self.physical(repo.root).path)
        #expect(trace.count == 6)
        #expect(trace.failures.isEmpty)
        #expect(raw.log.spawned.isEmpty)
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
        init(failAt: Int? = nil) { self.failAt = failAt }
        func check() throws {
            let count = lock.withLock { calls += 1; return calls }
            if count == failAt { throw FixtureMiss(command: "post-command fixture protection") }
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
