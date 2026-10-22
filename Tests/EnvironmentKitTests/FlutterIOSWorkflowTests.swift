import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("shared Flutter iOS workflow")
struct FlutterIOSWorkflowTests {
    @Test("prepared Flutter host builds without dependency alignment or installation")
    func build() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.selection?.selected?.framework == .flutter)
        #expect(result.operation.selection?.candidates.count == 1)
        #expect(result.up?.stages.map(\.id) == ["validate", "device", "build"])
        #expect(result.up?.context.product?.bundleIdentifier == "dev.test.flutter")
        #expect(!runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") || $0.arguments.contains("get") })
        #expect(!runner.commands.contains { $0.executable == "node" || $0.executable.hasSuffix("/bin/flutter") })
    }

    @Test("selected Flutter build uses the concrete Simulator without booting or taking its runtime lease")
    func selectedBuild() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "shutdown-device")
        let device = try f.leases.acquire([.device(.ios, "A")], owner: LeaseOwner(
            operationId: "other-app", command: "up", project: "/other-app"))
        defer { device.release() }
        let result = await WorkflowExecution.run(.build, input: f.input(device: "A"), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.device == "A")
        #expect(result.up?.context.device?.udid == "A")
        let build = try #require(runner.commands.first { $0.arguments.last == "build" })
        #expect(build.arguments.contains("platform=iOS Simulator,id=A"))
        #expect(build.arguments.contains("ONLY_ACTIVE_ARCH=YES"))
        #expect(!build.arguments.contains { $0.hasPrefix("ARCHS=") })
        #expect(build.executable == "/usr/bin/sandbox-exec")
        let output = try RunLogs(project: f.app).derivedDataDirectory.path
        for command in runner.commands where command.arguments.last == "build" || command.arguments.contains("-showBuildSettings") {
            let index = try #require(command.arguments.firstIndex(of: "-derivedDataPath"))
            #expect(command.arguments[index + 1] == output)
        }
        #expect(!runner.commands.contains { $0.arguments.contains("bootstatus") || $0.arguments.contains("boot") || $0.arguments.contains("install") || $0.arguments.contains("launch") })
        #expect(try InstallRecord.read(from: RunLogs(project: f.repo.root)) == nil)
    }

    @Test("Flutter build requires an unambiguous compatible Simulator", arguments: ["two-devices", "no-devices", "old-device", "unavailable-device", "invalid-device"])
    func buildDeviceSelection(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let selected = fault == "invalid-device" ? "missing" : ["old-device", "unavailable-device"].contains(fault) ? "A" : nil
        let result = await WorkflowExecution.run(.build, input: f.input(device: selected),
            runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.requiredInput.contains("--device") || result.up?.failure?.message.contains("device") == true)
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("bootstatus") || $0.arguments.contains("install") || $0.arguments.contains("launch") })
    }

    @Test("doctor shares prepared Flutter facts and keeps Android preparation independent")
    func doctor() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = try await EnvironmentInspection.run(input: f.input().project, runner: runner)
        #expect(result.report.checks.contains { $0.id == "flutter.sdk" && $0.status == .pass })
        #expect(result.report.checks.contains { $0.id == "ios.flutter.generated" && $0.status == .pass })
        #expect(!runner.commands.contains { $0.arguments.contains("build") || $0.arguments.contains("get") })
    }

    @Test("doctor grades the selected Flutter app deployment target against observed runtimes", arguments: [
        "available", "missing", "older", "malformed",
    ])
    func doctorRuntime(_ runtime: String) async throws {
        let f = try FlutterIOSFixture()
        try f.repo.write("ios/Podfile", "# platform :ios, '15.0'\n")
        let runner = FlutterIOSRunner(fixture: f, fault: "runtime:" + runtime)
        let result = try await EnvironmentInspection.run(input: f.input().project, runner: runner,
            scheme: "Runner", configuration: "Debug")
        let expected: CheckStatus = runtime == "available" ? .pass : runtime == "malformed" ? .unknown : .error
        let project = try #require(result.report.checks.first { $0.id == "ios.flutter.project" })
        #expect(project.status == expected)
        #expect(project.outcome.required == "an iOS 15.0 or newer simulator runtime, available")
        #expect(project.outcome.source.tier == 1)
        #expect(result.report.status == expected)
        #expect(result.exitCode == (expected == .error ? 1 : 0))
        #expect(!result.report.checks.contains { $0.id == "simulator.runtime" })
        #expect(result.selection.requiredInput.isEmpty)
        #expect(runner.commands.filter { $0.arguments.contains("-showBuildSettings") }.count == 1)
        #expect(runner.commands.filter { $0.arguments == ["simctl", "list", "runtimes", "-j"] }.count == 2)
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("install") || $0.arguments.contains("launch") })
        if runtime == "malformed" {
            #expect(project.outcome.reason?.contains("simctl stopped listing runtimes") == true)
            #expect(!result.report.hasToolFailure)
        }
    }

    @Test("doctor does not inspect an unresolved Flutter scheme's build settings or runtime")
    func doctorSchemeSelection() async throws {
        let f = try FlutterIOSFixture()
        try f.repo.write("ios/Podfile", "# platform :ios, '15.0'\n")
        try f.repo.write("ios/Runner.xcodeproj/xcshareddata/xcschemes/Other.xcscheme",
            "<Scheme><LaunchAction><BuildableProductRunnable><BuildableReference BlueprintName=\"Runner\" BuildableName=\"Runner.app\"/></BuildableProductRunnable></LaunchAction></Scheme>")
        let runner = FlutterIOSRunner(fixture: f, fault: "multiple-schemes")
        let result = try await EnvironmentInspection.run(input: f.input().project, runner: runner)
        #expect(result.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .warning })
        #expect(result.report.status == .warning)
        #expect(!result.report.checks.contains { $0.id == "simulator.runtime" })
        #expect(!runner.commands.contains { $0.arguments.contains("-showBuildSettings") || $0.arguments.last == "build" })
        #expect(runner.commands.filter { $0.arguments == ["simctl", "list", "runtimes", "-j"] }.count == 1)
    }

    @Test("doctor retains the generic runtime unknown while the Flutter SDK is unresolved")
    func doctorUnresolvedSDKRuntime() async throws {
        let f = try FlutterIOSFixture()
        try f.repo.write("ios/Podfile", "# platform :ios, '15.0'\n")
        try FileManager.default.removeItem(at: f.repo.url("sdk"))
        let runner = FlutterIOSRunner(fixture: f)
        let result = try await EnvironmentInspection.run(input: f.input().project, runner: runner,
            scheme: "Runner", configuration: "Debug")
        #expect(result.report.checks.contains { $0.id == "simulator.runtime" && $0.status == .unknown })
        #expect(!result.report.checks.contains { $0.id == "ios.flutter.project" })
        #expect(!runner.commands.contains { $0.arguments.contains("-showBuildSettings") || $0.arguments.last == "build" })
        #expect(runner.commands.filter { $0.arguments == ["simctl", "list", "runtimes", "-j"] }.count == 1)
    }

    @Test("up observes its own authenticated VM URI and down needs no SDK", arguments: [false, true], [false, true])
    func upAndDown(workspace: Bool, explicitPort: Bool) async throws {
        let f = try FlutterIOSFixture(workspace: workspace)
        let runner = FlutterIOSRunner(fixture: f)
        let events = Mutable<[String]>([])
        let requestedPort = explicitPort ? try FlutterIOSWorkflow.availablePort(nil) : nil
        let result = await WorkflowExecution.run(.up, input: f.input(port: requestedPort), runner: runner, leases: f.leases) { event in
            if let line = try? event.encoded() { events.mutate { $0.append(line) } }
        }
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        let port = try #require(result.operation.port)
        if let requestedPort { #expect(port == requestedPort) }
        #expect(result.operation.developmentServiceURI == "http://127.0.0.1:\(port)/auth/")
        #expect(result.up?.stages.map(\.id) == ["validate", "device", "build", "install", "launch"])
        let launch = try #require(runner.commands.first { $0.arguments.contains("launch") })
        #expect(launch.arguments.contains("--vm-service-port=\(port)"))
        #expect(!launch.arguments.contains("-RCT_jsLocation"))
        #expect(!runner.commands.contains { $0.arguments.contains { $0.hasPrefix("RCT_METRO_PORT=") } })
        #expect(try RunLogs(project: f.app).metroPort() == nil)
        #expect(launch.arguments.contains("A"))
        #expect(runner.commands.contains { $0.arguments.last == "http://127.0.0.1:\(port)/auth/getVM" })
        #expect(runner.commands.contains { $0.arguments.contains("show") })
        #expect(runner.commands.contains { $0.arguments.contains("get_app_container") })
        #expect(!events.value.joined().contains("/auth/"))
        #expect(!runner.commands.map(\.description).joined().contains("/auth/"))
        try FileManager.default.removeItem(at: f.repo.url("sdk"))
        if workspace {
            let key = ResourceKey.folder(try FolderIdentity(directory: f.repo.root))
            let owner = LeaseOwner(operationId: "workspace-setup", command: "setup", project: f.repo.root.path)
            let held = try f.leases.acquire([key], owner: owner)
            let beforeDown = runner.commands.count
            let blocked = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)
            #expect(blocked.exitCode == 1)
            #expect(blocked.operation.conflict?.key == key)
            #expect(blocked.operation.conflict?.owner == owner)
            #expect(runner.commands.count == beforeDown)
            #expect(try InstallRecord.read(from: RunLogs(project: f.app))?.bundleId == "dev.test.flutter")
            held.release()
        }
        let down = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)
        #expect(down.exitCode == 0)
        #expect(down.down?.items.map(\.id) == ["app"])
        #expect(down.down?.items.first?.status == .stopped)
        #expect(!runner.commands.contains { $0.arguments.contains("shutdown") || $0.arguments.contains("uninstall") || $0.arguments.contains("8081") })
    }

    @Test("bounded history readiness retains the install owner and SDK-less down")
    func historyUpAndDown() async throws {
        let f = try FlutterIOSFixture()
        let source = try Data(contentsOf: f.repo.url("lib/main.dart"))
        let lock = try Data(contentsOf: f.repo.url("pubspec.lock"))
        let runner = FlutterIOSRunner(fixture: f, fault: "history:ready")
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        let port = try #require(result.operation.port)
        #expect(result.operation.developmentServiceURI == "http://127.0.0.1:\(port)/synthetic-auth/")
        #expect(result.up?.context.appPid == 3538)
        #expect(try InstallRecord.read(from: RunLogs(project: f.repo.root))?.bundleId == "dev.test.flutter")
        #expect(try Data(contentsOf: f.repo.url("lib/main.dart")) == source)
        #expect(try Data(contentsOf: f.repo.url("pubspec.lock")) == lock)
        try FileManager.default.removeItem(at: f.repo.url("sdk"))
        let down = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)
        #expect(down.exitCode == 0)
        #expect(down.down?.items.first?.status == .stopped)
        #expect(!runner.commands.contains { $0.arguments.contains("shutdown") || $0.arguments.contains("uninstall") })
        let lease = try f.leases.acquire([.port(port)], owner: LeaseOwner(operationId: "after-down", command: "up", project: f.repo.root.path))
        lease.release()
    }

    @Test("a source change during historical observation fails without restoring source")
    func historySourceChange() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "history:source")
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(result.up?.failure != nil)
        #expect(result.operation.remaining.contains { $0.contains("lib/main.dart") })
        #expect(try String(contentsOf: f.repo.url("lib/main.dart"), encoding: .utf8) == "changed by query fixture\n")
        #expect(try InstallRecord.read(from: RunLogs(project: f.repo.root))?.bundleId == "dev.test.flutter")
        let down = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)
        #expect(down.exitCode == 0)
    }

    @Test("effective Release, changed target and Xcode fallback never reach build", arguments: ["release", "target", "configuration"])
    func effectiveInputs(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
    }

    @Test("effective Xcode settings cannot select an alternate Flutter engine", arguments: [
        "FLUTTER_TOOL_ARGS", "FLUTTER_ENGINE", "LOCAL_ENGINE", "LOCAL_ENGINE_HOST", "FLUTTER_ENGINE_SRC_PATH",
    ])
    func alternateEngine(_ setting: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: "engine:" + setting)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" })
    }

    @Test("a custom debug configuration requires selection and is shared with doctor")
    func configurationSelection() async throws {
        let f = try FlutterIOSFixture()
        let missing = FlutterIOSRunner(fixture: f, fault: "no-debug")
        let selection = await WorkflowExecution.run(.build, input: f.input(), runner: missing, leases: f.leases)
        #expect(selection.operation.state == "needs-selection")
        #expect(selection.operation.requiredInput == ["--configuration"])
        #expect(selection.operation.configurations == ["Development", "Release"])
        #expect(!missing.commands.contains { $0.arguments.contains("-showBuildSettings") || $0.arguments.last == "build" })
        let doctor = try await EnvironmentInspection.run(input: f.input().project, runner: missing)
        #expect(doctor.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .warning })
        let selected = FlutterIOSRunner(fixture: f, fault: "no-debug")
        let ready = try await EnvironmentInspection.run(input: f.input().project, runner: selected,
            scheme: "Runner", configuration: "Development")
        #expect(ready.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .pass })
        let build = await WorkflowExecution.run(.build, input: f.input(configuration: "Development"), runner: selected, leases: f.leases)
        #expect(build.exitCode == 0, Comment(rawValue: build.up?.failure?.message ?? ""))
        #expect(build.operation.configuration == "Development")
        let invalid = try await EnvironmentInspection.run(input: f.input().project, runner: selected, scheme: "Missing")
        #expect(invalid.report.checks.contains { $0.id == "ios.flutter.project" && $0.status == .error })
    }

    @Test("an explicit matching entrypoint uses existing generated inputs without rewriting them")
    func entrypoint() async throws {
        let f = try FlutterIOSFixture()
        try f.repo.write("lib/start.dart", "void main() {}\n")
        let generated = "FLUTTER_ROOT=\(f.repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(f.repo.root.path)\nFLUTTER_TARGET=lib/start.dart\n"
        try f.repo.write("ios/Flutter/Generated.xcconfig", generated)
        let runner = FlutterIOSRunner(fixture: f, fault: "entrypoint")
        let result = await WorkflowExecution.run(.build, input: f.input(entrypoint: "lib/start.dart"), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.entrypoint == f.repo.url("lib/start.dart").path)
        #expect(try String(contentsOf: f.repo.url("ios/Flutter/Generated.xcconfig"), encoding: .utf8) == generated)
    }

    @Test("missing and escaping entrypoints stop before any child", arguments: ["lib/missing.dart", "../outside.dart"])
    func invalidEntrypoint(_ entrypoint: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(entrypoint: entrypoint), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(runner.commands.isEmpty)
    }

    @Test("stale generated input, SDK bootstrap and missing Pods stop before native changes", arguments: ["generated", "sdk", "pods"])
    func preparation(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let file = fault == "generated" ? "ios/Flutter/Generated.xcconfig" : fault == "sdk" ? "sdk/bin/cache/flutter_tools.stamp" : "ios/Pods/Manifest.lock"
        try f.repo.write(file, "stale\n")
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("get") || $0.arguments.contains("install") })
        #expect(try String(contentsOf: f.repo.url(file), encoding: .utf8) == "stale\n")
    }

    @Test("a symlink pubspec lock is rejected by the existing regular-file preparation check")
    func symlinkPubspecLock() async throws {
        let f = try FlutterIOSFixture()
        let outside = try FixtureRepo()
        let file = try outside.write("external.lock", "packages: {}\n")
        let link = f.repo.url("pubspec.lock")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        var observed = link
        observed.removeAllCachedResourceValues()
        let attributes = try observed.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        #expect(attributes.isSymbolicLink == true)
        #expect(attributes.isRegularFile == false)
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(result.up?.context.validation?.checks.contains { $0.id == "dependencies.flutter" && $0.status == .error } == true)
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("install") })
        #expect(try String(contentsOf: file, encoding: .utf8) == "packages: {}\n")
        print("#208 symlink lock receipt: isRegularFile=\(attributes.isRegularFile == true); isSymbolicLink=\(attributes.isSymbolicLink == true); workflowExit=\(result.exitCode)")
    }

    @Test("build failure, cancellation and unexpected source changes preserve the failure boundary", arguments: ["build", "cancel", "source", "sdk-write"])
    func buildFailure(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == (fault == "cancel" ? 130 : 1), Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(!runner.commands.contains { $0.arguments.contains("install") || $0.arguments.contains("launch") })
        if fault == "source" {
            #expect(try String(contentsOf: f.repo.url("pubspec.lock"), encoding: .utf8) == "changed\n")
            #expect(result.operation.remaining.contains { $0.contains("pubspec.lock") })
        }
    }

    @Test("install, launch and invalid service results do not report development readiness", arguments: ["install", "launch", "uri", "not-vm"])
    func runtimeFailure(_ fault: String) async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f, fault: fault)
        let result = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.developmentServiceURI == nil)
        if fault == "install" { #expect(!runner.commands.contains { $0.arguments.contains("launch") }) }
        if fault == "uri" { #expect(!runner.commands.contains { $0.arguments.last?.contains("example.com") == true }) }
    }

    @Test("a port lease conflict stops before build and preserves its owner")
    func portLease() async throws {
        let f = try FlutterIOSFixture()
        let port = try FlutterIOSWorkflow.availablePort(nil)
        let other = try f.leases.acquire([.port(port)], owner: LeaseOwner(operationId: "other", command: "up", project: "/other"))
        defer { other.release() }
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.up, input: f.input(port: port), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(result.operation.conflict?.key == .port(port))
        #expect(result.operation.conflict?.owner?.operationId == "other")
        #expect(!runner.commands.contains { $0.arguments.last == "build" || $0.arguments.contains("install") })
    }

    @Test("build rejects a development port before any tool")
    func buildPort() async throws {
        let f = try FlutterIOSFixture()
        let runner = FlutterIOSRunner(fixture: f)
        let result = await WorkflowExecution.run(.build, input: f.input(port: 12345), runner: runner, leases: f.leases)
        #expect(result.exitCode == 1)
        #expect(runner.commands.isEmpty)
    }

    @Test("a workspace app's confirmed legacy install keeps its app owner through SDK-less down")
    func workspaceLegacyInstallOwner() async throws {
        let f = try FlutterIOSFixture(workspace: true)
        let runner = FlutterIOSRunner(fixture: f)
        let up = await WorkflowExecution.run(.up, input: f.input(), runner: runner, leases: f.leases)
        try #require(up.exitCode == 0)
        let logs = RunLogs(project: f.app)
        let current = try logs.url(InstallRecord.fileName)
        let legacy = logs.directory.appendingPathComponent(InstallRecord.fileName)
        let bytes = try Data(contentsOf: current)
        try FileManager.default.moveItem(at: current, to: legacy)
        try FileManager.default.removeItem(at: f.repo.url("sdk"))

        let down = await WorkflowExecution.run(.down, input: f.input(), runner: runner, leases: f.leases)

        #expect(down.exitCode == 0)
        #expect(down.down?.items.first?.status == .stopped)
        #expect(try Data(contentsOf: legacy) == bytes)
        #expect(!FileManager.default.fileExists(atPath: current.path))
        #expect(try InstallRecord.read(from: logs, leases: f.leases, ownerProject: f.app.path)?.bundleId == "dev.test.flutter")
    }

    @Test("Dart resolver workspace and selected app identity remain distinct in doctor and workflow")
    func workspaceIdentity() async throws {
        let f = try FlutterIOSFixture(workspace: true)
        let runner = FlutterIOSRunner(fixture: f)
        let staticSelection = try f.input().project.selection()
        let doctor = try await EnvironmentInspection.run(input: f.input().project, runner: runner)
        let result = await WorkflowExecution.run(.build, input: f.input(), runner: runner, leases: f.leases)
        #expect(result.exitCode == 0, Comment(rawValue: result.up?.failure?.message ?? ""))
        #expect(result.operation.selection?.selected?.id == staticSelection.selected?.id)
        #expect(result.operation.selection?.selected?.app == staticSelection.selected?.app)
        #expect(result.operation.selection?.selected?.workspace == (try FolderIdentity(directory: f.repo.root)))
        #expect(doctor.selection.selected == result.operation.selection?.selected)
        #expect(result.operation.selection?.selected?.app != result.operation.selection?.selected?.workspace)
        #expect(!runner.commands.contains { $0.arguments.contains("get") })
    }
}

struct FlutterIOSFixture {
    let flutter: FlutterFixture
    let inWorkspace: Bool
    var repo: FixtureRepo { flutter.repo }
    var app: URL { inWorkspace ? repo.url("apps/client") : repo.root }
    var leases: ResourceLeases { ResourceLeases(directory: repo.url("leases")) }
    var settings: [String: String] {
        ["CONFIGURATION": "Debug", "PLATFORM_NAME": "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
         "FULL_PRODUCT_NAME": "Runner.app", "BUILT_PRODUCTS_DIR": repo.url("build").path,
         "PRODUCT_BUNDLE_IDENTIFIER": "dev.test.flutter", "FLUTTER_BUILD_MODE": "debug",
         "FLUTTER_ROOT": repo.url("sdk").path, "FLUTTER_APPLICATION_PATH": app.path,
         "FLUTTER_TARGET": "lib/main.dart"]
    }
    init(workspace: Bool = false) throws {
        flutter = try FlutterFixture()
        inWorkspace = workspace
        try repo.write("ios/Runner.xcodeproj/project.pbxproj", "// fixture")
        try repo.write("ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme", "<Scheme><LaunchAction><BuildableProductRunnable><BuildableReference BlueprintName=\"Runner\" BuildableName=\"Runner.app\"/></BuildableProductRunnable></LaunchAction></Scheme>")
        try repo.write("ios/Runner.xcworkspace/contents.xcworkspacedata", "<Workspace><FileRef location=\"group:Runner.xcodeproj\"/></Workspace>")
        try repo.write("ios/Podfile.lock", "PODS:\n  - Flutter (1.0.0)\n")
        try repo.write("ios/Pods/Manifest.lock", "PODS:\n  - Flutter (1.0.0)\n")
        try repo.write(".xcode-version", "27.1\n")
        try repo.write("sdk/bin/cache/flutter_tools.stamp", FlutterFixture.revision + ":")
        try repo.write("sdk/bin/internal/engine.version", String(repeating: "a", count: 40))
        try repo.write("sdk/bin/cache/engine.stamp", String(repeating: "a", count: 40))
        try repo.write("sdk/bin/cache/engine-dart-sdk.stamp", String(repeating: "a", count: 40))
        try repo.write("sdk/packages/flutter_tools/pubspec.yaml", "name: flutter_tools\n")
        try repo.write("sdk/packages/flutter_tools/pubspec.lock", "packages: {}\n")
        try repo.write("sdk/bin/cache/artifacts/engine/ios/Flutter.xcframework/Info.plist", "engine")
        try repo.directory("home/Library/Application Support/dev.runstir/flutter/pub-cache")
        if workspace {
            try repo.directory("apps/client")
            for name in ["ios", "android", "lib", ".flutter-plugins-dependencies"] {
                try FileManager.default.moveItem(at: repo.url(name), to: app.appendingPathComponent(name))
            }
            let original = try String(contentsOf: repo.url("pubspec.yaml"), encoding: .utf8)
            try repo.write("pubspec.yaml", original + "workspace:\n  - apps/*\n")
            try repo.write("apps/client/pubspec.yaml", "name: client\nenvironment:\n  sdk: ^3.6.0\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n")
            try repo.write("apps/client/ios/Flutter/Generated.xcconfig", "FLUTTER_ROOT=\(repo.url("sdk").path)\nFLUTTER_APPLICATION_PATH=\(app.path)\nFLUTTER_TARGET=lib/main.dart\n")
            let packages = [("example", repo.root), ("client", app), ("flutter", repo.url("sdk/packages/flutter"))]
            try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages.map { ["name": $0.0, "rootUri": $0.1.absoluteString] }]).write(to: repo.url(".dart_tool/package_config.json"))
            try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": ["example", "client"], "packages": packages.map {
                ["name": $0.0, "dependencies": $0.0 == "flutter" ? [] : ["flutter"], "devDependencies": []] as [String: Any]
            }]).write(to: repo.url(".dart_tool/package_graph.json"))
        }
    }
    func input(entrypoint: String? = nil, port: Int? = nil, configuration: String? = nil, device: String? = nil) -> WorkflowInput {
        WorkflowInput(project: ProjectInspectionInput(directory: app, environment: flutter.environment,
            platform: .ios, entrypoint: entrypoint), device: device, configuration: configuration, port: port)
    }

    func configureIOSPlugin(directory: URL, name: String = "owned_plugin") throws {
        try "name: \(name)\nflutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: OwnedPlugin\n".write(
            to: directory.appendingPathComponent("pubspec.yaml"), atomically: false, encoding: .utf8)
        let manifest = try String(contentsOf: app.appendingPathComponent("pubspec.yaml"), encoding: .utf8)
        try (manifest + "  \(name): any\n").write(to: app.appendingPathComponent("pubspec.yaml"), atomically: false, encoding: .utf8)
        var config = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repo.url(".dart_tool/package_config.json"))) as? [String: Any])
        var packages = try #require(config["packages"] as? [[String: Any]])
        packages.append(["name": name, "rootUri": directory.absoluteString])
        config["packages"] = packages
        try JSONSerialization.data(withJSONObject: config).write(to: repo.url(".dart_tool/package_config.json"))
        var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repo.url(".dart_tool/package_graph.json"))) as? [String: Any])
        var nodes = try #require(graph["packages"] as? [[String: Any]])
        for index in nodes.indices where nodes[index]["name"] as? String == (inWorkspace ? "client" : "example") {
            var dependencies = try #require(nodes[index]["dependencies"] as? [String])
            dependencies.append(name)
            nodes[index]["dependencies"] = dependencies
        }
        nodes.append(["name": name, "dependencies": [], "devDependencies": []])
        graph["packages"] = nodes
        try JSONSerialization.data(withJSONObject: graph).write(to: repo.url(".dart_tool/package_graph.json"))
        let row: [String: Any] = ["name": name, "path": directory.path, "native_build": true]
        try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": ["ios": [row], "android": []]])
            .write(to: app.appendingPathComponent(".flutter-plugins-dependencies"))
    }
}

final class FlutterIOSRunner: ProcessRunner, @unchecked Sendable {
    static let processImageUUID = "FE1A2C8F-0D59-3D15-949C-1EF343B91FD6"
    static let senderImageUUID = "4C4C4413-5555-3144-A191-DFEC12239C3C"
    let fixture: FlutterIOSFixture
    let fault: String?
    private let lock = NSLock()
    private var recorded: [ProcessCommand] = []
    private var launchedPort: String?
    private var historyQueries = 0
    private var appRunning = false
    var commands: [ProcessCommand] { lock.withLock { recorded } }
    var installedBundle: URL {
        fixture.repo.url(fault == "history:quoted" ? "build/installed/Quote \" ' \\ App.app" : "build/installed/Runner.app")
    }
    var installedExecutable: String { installedBundle.appendingPathComponent("Runner").path }
    init(fixture: FlutterIOSFixture, fault: String? = nil) { self.fixture = fixture; self.fault = fault }
    func run(_ command: ProcessCommand, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        lock.withLock { recorded.append(command) }
        var command = command
        if command.executable == "/usr/bin/sandbox-exec" {
            command = ProcessCommand("xcodebuild", Array(command.arguments.dropFirst(3)), environment: command.environment,
                workingDirectory: command.workingDirectory, timeout: command.timeout, output: command.output)
        }
        if command.executable == "xcodebuild" {
            if command.arguments == ["-version"] { return ok("Xcode 27.1\nBuild version 27A9275") }
            if command.arguments == ["-checkFirstLaunchStatus"] { return ok("") }
            if command.arguments.contains("-list") {
                let configurations = fault == "no-debug" ? ["Development", "Release"] : ["Debug", "Release"]
                let schemes = fault == "multiple-schemes" ? ["Runner", "Other"] : ["Runner"]
                return ok(String(decoding: try JSONSerialization.data(withJSONObject:
                    ["project": ["schemes": schemes, "configurations": configurations]]), as: UTF8.self))
            }
            if command.arguments.contains("-showBuildSettings") {
                var settings = fixture.settings
                if fault == "release" { settings["FLUTTER_BUILD_MODE"] = "release" }
                if fault == "target" { settings["FLUTTER_TARGET"] = "lib/other.dart" }
                if fault == "entrypoint" { settings["FLUTTER_TARGET"] = "lib/start.dart" }
                if fault == "configuration" { settings["CONFIGURATION"] = "Release" }
                if let fault, fault.hasPrefix("engine:") { settings[String(fault.dropFirst("engine:".count))] = "/unapproved/engine" }
                if fault == "no-debug", let option = command.arguments.firstIndex(of: "-configuration") {
                    settings["CONFIGURATION"] = command.arguments[option + 1]
                }
                return ok(String(decoding: try JSONSerialization.data(withJSONObject: [["target": "Runner", "buildSettings": settings]]), as: UTF8.self))
            }
            if command.arguments.last == "build" {
                if fault == "real-child" {
                    try FileManager.default.createDirectory(at: fixture.repo.url("build"), withIntermediateDirectories: true)
                    let selected = try #require(commands.last)
                    let profile = try #require(selected.arguments.dropFirst().first)
                    return try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": fixture.repo.url("home").path], workingDirectory: fixture.repo.root)
                        .run(ProcessCommand("/usr/bin/sandbox-exec", ["-f", profile, "/bin/sh", "-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "_", fixture.repo.url("build/child.pid").path], timeout: .seconds(40)))
                }
                if fault == "source" { try fixture.repo.write("pubspec.lock", "changed\n") }
                if fault == "sdk-write" { try fixture.repo.write("sdk/bin/cache/flutter_tools.snapshot", "changed\n") }
                if fault == "cancel" { throw CancellationError() }
                if fault == "build" { return ProcessResult(terminationStatus: .exited(65), standardOutput: "", standardError: "build failed") }
                return ok("")
            }
        }
        if command.executable == "/usr/bin/xcrun", command.arguments.starts(with: ["dwarfdump", "--uuid"]) {
            let path = try #require(command.arguments.last)
            let uuid = path == installedExecutable ? Self.processImageUUID : Self.senderImageUUID
            if fault == "history:uuid-cancel" { return try await finiteQuery(command) }
            if fault == "history:uuid-failed" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "private identity output", standardError: "private identity error") }
            if fault == "history:uuid-empty" { return ok("") }
            if fault == "history:uuid-malformed" { return ok("UUID: not-a-UUID (arm64) \(path)") }
            if fault == "history:uuid-oversized" { return ok(String(repeating: "a", count: 1_048_577)) }
            let line = "UUID: \(uuid) (\(fault == "history:uuid-arch" ? "arm64;invalid" : "arm64")) \(path)\(fault == "history:uuid-path" ? ".other" : "")\n"
            if fault == "history:uuid-duplicate" { return ok(line + line) }
            if fault == "history:uuid-too-many" { return ok(String(repeating: line, count: 17)) }
            if fault == "history:uuid-fat" { return ok(line + "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (x86_64) \(path)\n") }
            return ok(line)
        }
        if command.executable == "lsof" {
            return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "")
        }
        if command.executable == "curl", command.arguments.last?.hasSuffix("getVM") == true {
            if fault == "history:probe-timeout" { throw ProcessError.timedOut(command: command.description, timeout: command.timeout ?? .seconds(5)) }
            if fault == "history:dies-after-probe" { lock.withLock { appRunning = false } }
            return ok(fault == "not-vm" ? "{}" : "{\"result\":{\"type\":\"VM\"}}")
        }
        if command.arguments.starts(with: ["simctl", "install"]) {
            if fault == "install" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "install failed") }
            return ok("")
        }
        if command.arguments.starts(with: ["simctl", "terminate"]) {
            lock.withLock { appRunning = false }
            return ok("")
        }
        if command.arguments == ["simctl", "spawn", "A", "launchctl", "list"] {
            let running = lock.withLock { appRunning }
            let pid = fault == "history:reused" ? "3539" : "3538"
            return ok(running && fault != "history:dead" ? "\(pid)\t0\tUIKitApplication:dev.test.flutter[fixture]" : "-\t0\tUIKitApplication:dev.test.flutter[fixture]")
        }
        if command.arguments.starts(with: ["simctl", "get_app_container"]) {
            try FileManager.default.createDirectory(at: installedBundle, withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": "dev.test.flutter", "CFBundleExecutable": "Runner",
            ], format: .binary, options: 0)
            try info.write(to: installedBundle.appendingPathComponent("Info.plist"))
            try Data().write(to: installedBundle.appendingPathComponent("Runner"))
            let engine = installedBundle.appendingPathComponent("Frameworks/Flutter.framework/Flutter")
            try FileManager.default.createDirectory(at: engine.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: engine)
            if fault == "history:engine-symlink" || fault == "history:runner-symlink" {
                let file = fault == "history:engine-symlink" ? engine : installedBundle.appendingPathComponent("Runner")
                try FileManager.default.removeItem(at: file)
                let target = try fixture.repo.write("build/outside-image", "preserve")
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            }
            if fault == "history:engine-parent-link" {
                let framework = engine.deletingLastPathComponent()
                try FileManager.default.removeItem(at: framework)
                let outside = try fixture.repo.directory("build/outside-framework")
                try Data().write(to: outside.appendingPathComponent("Flutter"))
                try FileManager.default.createSymbolicLink(at: framework, withDestinationURL: outside)
            }
            return ok(fault == "history:control" ? installedBundle.path + "\nother" : installedBundle.path + "\n")
        }
        if command.arguments.starts(with: ["simctl", "spawn", "A", "log", "show"]) {
            let query = lock.withLock { historyQueries += 1; return historyQueries }
            if fault == "history:timeout" { throw ProcessError.timedOut(command: "private query http://127.0.0.1:12345/synthetic-auth/", timeout: command.timeout ?? .seconds(5)) }
            if fault == "history:spawn" {
                throw ProcessError.spawnFailed(command: "private query http://127.0.0.1:12345/synthetic-auth/",
                    underlying: NSError(domain: "private query diagnostic", code: 1))
            }
            if fault == "history:runner-error" { throw NSError(domain: "private query http://127.0.0.1:12345/synthetic-auth/", code: 1) }
            if fault == "history:deadline" {
                try await Task.sleep(for: command.timeout ?? .milliseconds(25))
                throw ProcessError.timedOut(command: "private history output", timeout: command.timeout ?? .milliseconds(25))
            }
            if fault == "history:cancel" { return try await finiteQuery(command) }
            if fault == "history:malformed" { return ok("private query http://127.0.0.1:12345/synthetic-auth/ not JSON") }
            if fault == "history:failed" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "private query output", standardError: "private query diagnostic") }
            if fault == "history:signaled" { return ProcessResult(terminationStatus: .signaled(9), standardOutput: "private query output", standardError: "private query diagnostic") }
            if fault == "history:oversized" { return ok("private query http://127.0.0.1:12345/synthetic-auth/" + String(repeating: " ", count: 1_048_577)) }
            if fault == "history:many" { return ok(String(decoding: try JSONSerialization.data(withJSONObject: Array(repeating: ["eventMessage": "private query http://127.0.0.1:12345/synthetic-auth/"] as [String: String], count: 1025)), as: UTF8.self)) }
            if fault == "no-uri" || fault == "history:empty" || (fault == "history:delayed" && query == 1) { return ok("[]") }
            if fault == "history:source" { try fixture.repo.write("lib/main.dart", "changed by query fixture\n") }
            let port = lock.withLock { launchedPort } ?? "12345"
            let selectedPort = fault == "history:port" ? "12346" : port
            let date = Date().addingTimeInterval(fault == "history:old" ? -3600 : fault == "history:future" ? 3600 : 0)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let fraction = Int((date.timeIntervalSince1970 - floor(date.timeIntervalSince1970)) * 1_000_000)
            let timestamp = formatter.string(from: date) + String(format: ".%06d+0000", fraction)
            let row: [String: Any] = [
                "processID": fault == "history:pid" ? 9999 : 3538,
                "processImagePath": fault == "history:stale-path" ? "/earlier-install/Runner.app/Runner" : fault == "history:exe" ? installedExecutable + ".other" : installedExecutable,
                "senderImagePath": fault == "history:stale-path" ? "/earlier-install/Runner.app/Frameworks/Flutter.framework/Flutter" : fault == "history:sender" ? "/other/image" : installedBundle.appendingPathComponent("Frameworks/Flutter.framework/Flutter").path,
                "processImageUUID": fault == "history:process-uuid" ? "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" : fault == "history:lowercase-uuid" ? Self.processImageUUID.lowercased() : Self.processImageUUID,
                "senderImageUUID": fault == "history:sender-uuid" ? "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" : fault == "history:lowercase-uuid" ? Self.senderImageUUID.lowercased() : Self.senderImageUUID,
                "timestamp": fault == "history:time" ? "unknown" : timestamp,
                "eventMessage": fault == "history:message-limit" ? String(repeating: "a", count: 16_385)
                    : "flutter: The Dart VM service is listening on " + (fault == "uri" ? "http://example.com:1/auth/"
                        : "http://127.0.0.1:\(selectedPort)/\(fault?.hasPrefix("history:") == true ? "synthetic-auth" : "auth")/"),
            ]
            var returnedRow = row
            if fault == "history:wrong-key" { returnedRow["processIdentifier"] = returnedRow.removeValue(forKey: "processID") }
            if fault == "history:boolean-pid" { returnedRow["processID"] = true }
            if fault == "history:missing-uuid" { returnedRow.removeValue(forKey: "senderImageUUID") }
            if fault == "history:invalid-uuid" { returnedRow["processImageUUID"] = "invalid" }
            if fault == "history:uuid-type" { returnedRow["processImageUUID"] = 1234 }
            return ok(String(decoding: try JSONSerialization.data(withJSONObject: [returnedRow], options: .prettyPrinted), as: UTF8.self))
        }
        if command.arguments.starts(with: ["simctl", "launch"]) {
            if fault == "launch" { return ProcessResult(terminationStatus: .exited(1), standardOutput: "", standardError: "launch failed") }
            let port = try #require(command.arguments.first { $0.hasPrefix("--vm-service-port=") })
            let value = String(port.dropFirst("--vm-service-port=".count))
            lock.withLock { launchedPort = value; appRunning = true }
            return ok("dev.test.flutter: 3538")
        }
        if command.executable == "xcode-select" { return ok("/test/Xcode") }
        if command.executable == "pod" { return ok("1.16.2") }
        if command.executable == "ruby" { return ok("ruby 3.2.2") }
        if command.arguments == ["simctl", "list", "runtimes", "-j"] {
            // CoreSimulator answers first; only the later requirement measurement changes.
            if fault?.hasPrefix("runtime:") == true,
               commands.filter({ $0.arguments == command.arguments }).count == 1 {
                return ok("{\"runtimes\":[{\"identifier\":\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\",\"name\":\"iOS 27.0\",\"version\":\"27.0\",\"isAvailable\":true}]}")
            }
            if fault == "runtime:missing" { return ok("{\"runtimes\":[]}") }
            if fault == "runtime:malformed" { return ok("not a runtime list") }
            let version = fault == "runtime:older" ? "14.9" : "27.0"
            return ok("{\"runtimes\":[{\"identifier\":\"com.apple.CoreSimulator.SimRuntime.iOS-\(version.replacingOccurrences(of: ".", with: "-"))\",\"name\":\"iOS \(version)\",\"version\":\"\(version)\",\"isAvailable\":true}]}")
        }
        if command.arguments == ["simctl", "list", "devices", "-j"] {
            let runtime = fault == "old-device" ? "14-0" : "27-0"
            let state = fault == "shutdown-device" ? "Shutdown" : "Booted"
            var devices: [[String: Any]] = [["name": "iPhone A", "udid": "A", "state": state, "isAvailable": fault != "unavailable-device"]]
            if fault == "two-devices" { devices.append(["name": "iPhone B", "udid": "B", "state": "Shutdown", "isAvailable": true]) }
            if fault == "no-devices" { devices = [] }
            return ok(String(decoding: try JSONSerialization.data(withJSONObject: ["devices": ["com.apple.CoreSimulator.SimRuntime.iOS-" + runtime: devices]]), as: UTF8.self))
        }
        let workspace = fixture.inWorkspace ? "{\"packages\":[{\"path\":\"\(fixture.repo.root.path)\"},{\"path\":\"\(fixture.app.path)\"}]}" : nil
        return try await fixture.flutter.runner(workspace: workspace).run(command, onLine: onLine)
    }
    func spawnDetached(_ command: ProcessCommand, logFile: URL) async throws -> Int32 { throw FixtureMiss(command: command.description) }
    private func finiteQuery(_ command: ProcessCommand) async throws -> ProcessResult {
        try FileManager.default.createDirectory(at: fixture.repo.url("build"), withIntermediateDirectories: true)
        return try await SystemProcessRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": fixture.repo.url("home").path])
            .run(ProcessCommand("/bin/sh", ["-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "_", fixture.repo.url("build/query.pid").path], timeout: command.timeout))
    }
    private func ok(_ text: String) -> ProcessResult { ProcessResult(terminationStatus: .exited(0), standardOutput: text, standardError: "") }
}
